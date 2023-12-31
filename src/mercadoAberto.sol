// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


import "openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
import "openzeppelin-contracts/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "openzeppelin-contracts/contracts/token/ERC1155/ERC1155.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "./interfaces/ITesouroDireto.sol";


contract openMarket is Ownable, ERC1155, ERC1155Holder, IERC721Receiver {

    //-----------------------------------------------------------------------------------------------
    //
    //                                      ERRORS
    //
    //-----------------------------------------------------------------------------------------------
    error NotTreasuryAddress(address _sender);
    error NotKYCed(address _sender);
    error paymentNotMade();
    error retrievalFailed(address _sender,uint256 _tokenId,uint256 _amount);
    //-----------------------------------------------------------------------------------------------
    //
    //                                      EVENTS
    //
    //-----------------------------------------------------------------------------------------------
    
    event publicOrderCreated(uint256 indexed _tokenId, uint256 indexed _units, uint256 _price);
    event primarySale(address indexed _sender, uint256 indexed _tokenId, uint256 indexed _amount);
    event retrievalsucceed(address _sender,uint256 _tokenId,uint256 _amount);
    event secondaryForSale(address indexed _seller, uint256 indexed _tokenId, uint256 indexed _units, uint256 _price);
    event secondarySold(address indexed _seller, address indexed _buyer, uint256 indexed _units, uint256 _price, uint256 _tokenId);

    //-----------------------------------------------------------------------------------------------
    //
    //                                      VARIABLES
    //
    //-----------------------------------------------------------------------------------------------

    struct buyInfo {
        uint256 _price;
        uint256 _avlb;
    }

    ITesouroDireto _treasury;
    IERC20 _wDREX;
    address _union;
    mapping(uint256 => buyInfo) public openBuy; //TokenId => buyInfo
    mapping(uint256 => mapping(address => buyInfo)) public secondaryMarket; //TokenId => buyInfo
    mapping (address => bool) public buyer; //KYC Users

    //-----------------------------------------------------------------------------------------------
    //
    //                                      CONSTRUCTOR
    //
    //-----------------------------------------------------------------------------------------------

    constructor(string memory _uri, address _payment, address __union) ERC1155(_uri) Ownable(msg.sender){
        _wDREX = IERC20(_payment);
        _union = __union;
        KYC(msg.sender);
    }

    //-----------------------------------------------------------------------------------------------
    //
    //                                 EXTERNAL FUNCTIONS
    //
    //-----------------------------------------------------------------------------------------------

    function setTreasury(address _addr) public /*onlyOwner*/ {
        _treasury = ITesouroDireto(_addr);
    }

    function KYC(address _KYCed) public /*onlyOwner*/{
        buyer[_KYCed] = true;
    }

    function purchasePrimary(uint256 _tokenId, uint256 _amount) public /*KYCed*/ {
        require(balanceOf(address(this), _tokenId) >= _amount, "mercadoAberto : Not enough availble");
        (uint256 _price, ) = _treasury.getPriceAmount(_tokenId);
        require(_wDREX.allowance(msg.sender, address(this)) >= _amount*_price, "mercadoAberto : Allowance not enough");

        if(!_wDREX.transferFrom(msg.sender, _union, _amount*_price)) revert paymentNotMade();

        _safeTransferFrom(address(this), msg.sender, _tokenId, _amount, "");

        emit primarySale(msg.sender, _tokenId, _amount);
    }

    function sellMyUnits(uint256 _tokenId, uint256 _units, uint256 _price) public /*KYCed*/ {
        require(balanceOf(msg.sender, _tokenId) >= _units, "mercadoAberto : Not enough units");
        require(isApprovedForAll(msg.sender, address(this)), "mercadoAberto : Not approved for contract");

        secondaryMarket[_tokenId][msg.sender] = buyInfo({_price: _price, _avlb: _units});

        emit secondaryForSale(msg.sender, _tokenId, _units, _price);
    }

    function buySecondary(address _seller, uint256 _tokenId, uint256 _units) public /*KYCed*/ {
        require(secondaryMarket[_tokenId][_seller]._avlb >= _units, "mercadoAberto : Trying to buy more than available");
        uint256 _price = secondaryMarket[_tokenId][_seller]._price * _units;
        require(_wDREX.balanceOf(msg.sender) >= _price, "mercadoAberto : Not enough money");
        require(_wDREX.allowance(msg.sender, address(this)) >= _price, "mercadoAberto : Allowance not enough");
        require(isApprovedForAll(_seller, address(this)), "mercadoAberto : Selelr Not approved for all");

        if(!_wDREX.transferFrom(msg.sender, _seller, _price)) revert paymentNotMade();

        _safeTransferFrom(_seller, msg.sender, _tokenId, _units, "");

        emit secondarySold(_seller, msg.sender, _units, _price, _tokenId);
        
    }

    function retrieveInvestment(uint256 _tokenId, uint256 _amount) public /*KYCed*/ {
        require(balanceOf(msg.sender, _tokenId) >= _amount, "mercadoAberto : Not enough units");
        require(isApprovedForAll(msg.sender, address(this)), "mercadoAberto : Not approved for contract");
        
        _burn(msg.sender, _tokenId, _amount);
        if(!_treasury.retriveFullInvestment(_tokenId, _amount)) revert retrievalFailed(msg.sender,_tokenId,_amount);

        emit retrievalsucceed(msg.sender, _tokenId, _amount);
    }

    //-----------------------------------------------------------------------------------------------
    //
    //                                 INTERNAL FUNCTIONS
    //
    //-----------------------------------------------------------------------------------------------


    function _createPublicOffer(uint256 _tokenId) internal {
        (uint256 _price, uint256 _available) = _treasury.getPriceAmount(_tokenId);
        _mint(address(this), _tokenId, _available, "");
        openBuy[_tokenId] = buyInfo({_price: _price,_avlb: _available});

        emit publicOrderCreated(_tokenId, _available, _price);
    }



    //-----------------------------------------------------------------------------------------------
    //
    //                                 GETTER FUNCTIONS
    //
    //-----------------------------------------------------------------------------------------------

    function getOpenBuy(uint256 _tokenId) external view returns(uint256, uint256){
        return(openBuy[_tokenId]._avlb,openBuy[_tokenId]._price);
    }

    function getSecondaryMarket(uint256 _tokenId, address _seller) external view returns(uint256, uint256){
        return(secondaryMarket[_tokenId][_seller]._avlb,secondaryMarket[_tokenId][_seller]._price);
    }

    //-----------------------------------------------------------------------------------------------
    //
    //                                      INHERITANCE
    //
    //-----------------------------------------------------------------------------------------------


    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) public override returns (bytes4) {
        _createPublicOffer(tokenId);
        return this.onERC721Received.selector;
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC1155,ERC1155Holder) returns (bool) {
        return
            interfaceId == type(IERC1155).interfaceId ||
            interfaceId == type(IERC1155MetadataURI).interfaceId ||
            interfaceId == type(IERC1155Receiver).interfaceId ||
            super.supportsInterface(interfaceId);
    }



    //-----------------------------------------------------------------------------------------------
    //
    //                                      MODIFIER
    //
    //-----------------------------------------------------------------------------------------------

    modifier onlyTreasury() {
        if(msg.sender != address(_treasury)) revert NotTreasuryAddress(msg.sender);
        _;
    }

    modifier KYCed() {
        if(!buyer[msg.sender]) revert NotKYCed(msg.sender);
        _;
    }
    modifier KYCcheck(address _check) {
        if(!buyer[_check]) revert NotKYCed(_check);
        _;
    }



}