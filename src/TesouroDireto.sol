// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@erc721a/ERC721A.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
//_packedOwnershipOf(tokenId); == previous ownership
contract tesouroDireto is ERC721A, Ownable(msg.sender){
    //-----------------------------------------------------------------------------------------------
    //
    //                                      ERRORS
    //
    //-----------------------------------------------------------------------------------------------

    error NotKYCed();
    error NotEmitter();
    error NotValidTreasuryType();
    error notOpenMarketContract(address _sender);

    //-----------------------------------------------------------------------------------------------
    //
    //                                      EVENTS
    //
    //-----------------------------------------------------------------------------------------------

    event treasuryCreated(uint256 indexed _tokenId, uint256 indexed _totalValue, uint256 indexed _apy, uint256 _duration, treasuryType);
    

    //-----------------------------------------------------------------------------------------------
    //
    //                                      VARIABLES
    //
    //-----------------------------------------------------------------------------------------------

    enum treasuryType{
        LTN, //PREFIXADO,O investidor conhece o retorno exato ao final da aplicação
        NTN_F, //descrito acima e que são pagos juros semestrais ao investidor 
        LFT, //POS-FIXADO que acompanha a variação da taxa Selic diariamente
        NTN_B_MAIN, //MISTO, combinando rentabilidade prefixada com o IPCA,
        NTN_B ////descrito acima e que são pagos juros semestrais ao investidor 
    }

    struct treasuryData{
        treasuryType _type;
        uint24 _apy;
        uint256 _minInvestment;
        uint256 _validThru;
        uint256 _avlbTokens;
        uint256 _creation;
    }

    address constant CCIP = 0x026fb7C16f1D0082809ff2335715f27e1e074fF6; //CCIP contract
    address constant CCIPaddr = 0xf58B1eB6B61444dcA38a2FfFC03FF59Cea2b2fA1;
    address public emitter; //Union wallet 
    mapping(address => bool) emmiters;
    address public openMarket;
    IERC20 _oracle;
    mapping (uint256 => treasuryData) public tokenInfo; //ERC721A to ERC1155

    //-----------------------------------------------------------------------------------------------
    //
    //                                      CONSTRUCTOR
    //
    //-----------------------------------------------------------------------------------------------
    constructor(string memory _name, string memory _symbol, address _openMarket, address _wdrex) ERC721A(_name,_symbol){
        emitter = msg.sender;
        emmiters[msg.sender] = true;
        emmiters[0x026fb7C16f1D0082809ff2335715f27e1e074fF6] = true;
        emmiters[0xf58B1eB6B61444dcA38a2FfFC03FF59Cea2b2fA1] = true;
        openMarket = _openMarket;
        _oracle = IERC20(_wdrex);
    }


    //-----------------------------------------------------------------------------------------------
    //
    //                                      PUBLIC FUNCTIONS
    //
    //-----------------------------------------------------------------------------------------------

    function emitTreasury(treasuryData memory _data) public /*onlyEmitter*/{
        _data._creation = block.timestamp;
        tokenInfo[_nextTokenId()] = _data;
        if (_data._type == treasuryType.LTN){
            ERC721A._safeMint(address(this), 1, "");
            ERC721A._setExtraDataAt(ERC721A._nextTokenId()-1, _data._apy);
        }else if(_data._type == treasuryType.NTN_F){
            ERC721A._safeMint(address(this), 1, "");
            ERC721A._setExtraDataAt(ERC721A._nextTokenId()-1, _data._apy);
        }else if(_data._type == treasuryType.LFT){
            ERC721A._safeMint(address(this), 1, "");
            ERC721A._setExtraDataAt(ERC721A._nextTokenId()-1, _data._apy);
        }else if(_data._type == treasuryType.NTN_B_MAIN){
            ERC721A._safeMint(address(this), 1, "");
            ERC721A._setExtraDataAt(ERC721A._nextTokenId()-1, _data._apy);
        }else if(_data._type == treasuryType.NTN_B){
            ERC721A._safeMint(address(this), 1, "");
            ERC721A._setExtraDataAt(ERC721A._nextTokenId()-1, _data._apy);
        }else{
            revert NotValidTreasuryType();
        }
        emit treasuryCreated(_nextTokenId()-1,_data._avlbTokens*_data._minInvestment, _data._apy, _data._validThru, _data._type);
    }

    function openPublicOffer(uint256 _tokenId) public /*onlyEmitter*/ {
        require(ownerOf(_tokenId) == address(this), "Tesouro Direto : Not in treasury ownership");
        ERC721A._tokenApprovals[_tokenId].value = msg.sender;
        safeTransferFrom(address(this), openMarket, _tokenId);
    }

    function retriveFullInvestment(uint256 _tokenId, uint256 _amount) external returns(bool){
        if(msg.sender != openMarket) revert notOpenMarketContract(msg.sender);

        (uint24 _apy, uint256 _years, uint256 _price, uint256 _creation) = getTokenInfo(_tokenId);

        require(block.timestamp >= _creation + _years, "Tesouro Direto : Cannot retrieve full amount yet");
        uint256 _value = (_price*_amount)*(_years/365 days)*_apy/10000;

        require(_oracle.transferFrom(address(_oracle), address(this), _value), "Tesouro Direto : Retrieval not possible");
        require(_oracle.transfer(tx.origin, _value), "Tesouro Direto : Retrieval not possible");

        return true;
    }

    function retrievePartialInvestment(uint256 _tokenId, uint256 _amount) external returns (bool){
        return true;
    }

    function setEmmiter(address _newemmit) external /*onlyOwner*/{
        emmiters[_newemmit] = true;
    }

    //-----------------------------------------------------------------------------------------------
    //
    //                                      INHERIT FROM ERC721A
    //
    //-----------------------------------------------------------------------------------------------

    function _extraData(
        address from,
        address to,
        uint24 previousExtraData
    ) internal pure override returns (uint24) {
        return previousExtraData;
    }

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) public returns (bytes4) {
        return this.onERC721Received.selector;
    }


    //-----------------------------------------------------------------------------------------------
    //
    //                                      GETTER FUNCTIONS
    //
    //-----------------------------------------------------------------------------------------------

    function getPriceAmount(uint256 _tokenId) external view returns(uint256 _price, uint256 _amount){
        _price = tokenInfo[_tokenId]._minInvestment;
        _amount = tokenInfo[_tokenId]._avlbTokens;
    }

    function getTokenInfo(uint256 _tokenId) public view returns(uint24 _apy, uint256 _validThru, uint256 _price, uint256 _creation){
        return(tokenInfo[_tokenId]._apy, tokenInfo[_tokenId]._validThru,tokenInfo[_tokenId]._minInvestment, tokenInfo[_tokenId]._creation);
    }


    //-----------------------------------------------------------------------------------------------
    //
    //                                      MODIFIERS
    //
    //-----------------------------------------------------------------------------------------------


    // modifier onlyEmitter() {
    //     if(msg.sender != emitter && msg.sender != CCIP && msg.sender != CCIPaddr) revert NotEmitter();
    //     _;
    // }

    modifier onlyEmitter() {
       require(emmiters[msg.sender] == true, "NOtEmmite");
        _;
    }

    
    
}