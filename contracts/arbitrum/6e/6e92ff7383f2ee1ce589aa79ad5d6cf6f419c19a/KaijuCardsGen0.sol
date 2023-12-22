// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IGen0 } from "./IGen0.sol";
import { LibKaijuCardsGen0Storage } from "./LibKaijuCardsGen0Storage.sol";
import { NftBurnBridgingBase, IWormhole } from "./NftBurnBridgingBase.sol";
import { ERC721Upgradeable } from "./ERC721Upgradeable.sol";
import { Ownable2StepUpgradeable } from "./Ownable2StepUpgradeable.sol";
import { StringsUpgradeable } from "./StringsUpgradeable.sol";
import { FacetInitializable } from "./FacetInitializable.sol";

contract KaijuCardsGen0 is IGen0, ERC721Upgradeable, NftBurnBridgingBase, Ownable2StepUpgradeable {
    // Disable implementation contract
    constructor() facetInitializer(keccak256("KaijuCardsGen0_init")) {}

    function KaijuCardsGen0_init(
        IWormhole _wormhole,
        uint16 _emitterChainId,
        bytes32 _emitterAddress
    ) external facetInitializer(keccak256("KaijuCardsGen0_init")) {
        __NftBurnBridgingBase_init(_wormhole, _emitterChainId, _emitterAddress);
        __ERC721_init("KaijuCardsGen0", "KC0");
        __Ownable2Step_init();

        LibKaijuCardsGen0Storage.Layout storage _l = LibKaijuCardsGen0Storage.layout();
        _l.allowStaking = true;
        _l.allowUnstaking = false;
        _l.baseUri = "https://assets.kaijucards.io/json/";
    }

    function isStaked(uint256 _tokenId) external view override returns (bool) {
        return LibKaijuCardsGen0Storage.layout().tokenIsStaked[_tokenId];
    }

    function stakeNft(uint256 _tokenId) external {
        LibKaijuCardsGen0Storage.Layout storage _l = LibKaijuCardsGen0Storage.layout();
        bool _isStaked = _l.tokenIsStaked[_tokenId];
        address owner = _ownerOf(_tokenId);

        require(_l.allowStaking, "Staking is not allowed at this time.");
        require(!_isStaked, "KaijuCardsGen0: token is already staked.");
        require(owner == msg.sender, "KaijuCardsGen0: caller is not owner.");

        _l.tokenIsStaked[_tokenId] = true;
        emit Staked(_tokenId);
    }

    function unstakeNft(uint256 _tokenId) external {
        LibKaijuCardsGen0Storage.Layout storage _l = LibKaijuCardsGen0Storage.layout();
        bool _isStaked = _l.tokenIsStaked[_tokenId];
        address owner = _ownerOf(_tokenId);

        require(_isStaked, "KaijuCardsGen0: token is not staked.");
        require(owner == msg.sender, "KaijuCardsGen0: caller is not owner.");
        require(_l.allowUnstaking, "Unstaking is not yet allowed at this time.");

        _l.tokenIsStaked[_tokenId] = false;
        emit Unstaked(_tokenId);
    }

    function setAllowUnstaking(bool _allow) external onlyOwner {
        LibKaijuCardsGen0Storage.layout().allowUnstaking = _allow;
        emit AllowUnstakingChanged(_allow);
    }

    function setAllowStaking(bool _allow) external onlyOwner {
        LibKaijuCardsGen0Storage.layout().allowStaking = _allow;
        emit AllowStakingChanged(_allow);
    }

    function setBaseURI(string calldata _uri) external onlyOwner {
        LibKaijuCardsGen0Storage.layout().baseUri = _uri;
        emit BaseUriChanged(_uri);
    }

    function tokenURI(uint256 _tokenId) public view override returns (string memory tokenUri_) {
        string memory _charPrefix = getCharPrefixFromId(_tokenId);
        uint256 _reducedTokenId = _tokenId % LibKaijuCardsGen0Storage.CHARACTER_TOKEN_OFFSET_AMOUNT;
        tokenUri_ = string.concat(LibKaijuCardsGen0Storage.layout().baseUri, _charPrefix, "-", StringsUpgradeable.toString(_reducedTokenId), ".json");
    }

    function supportsInterface(bytes4 _interfaceId) public view override returns (bool) {
        return _interfaceId == type(IGen0).interfaceId || super.supportsInterface(_interfaceId);
    }

    function _beforeTokenTransfer(
        address _from,
        address _to,
        uint256 _firstTokenId,
        uint256 _batchSize
    ) internal override {
        LibKaijuCardsGen0Storage.Layout storage _l = LibKaijuCardsGen0Storage.layout();
        // Will most likely be called with _batchSize = 1, however if needed it will support the consecutive token transfers
        for (uint i = 0; i < _batchSize; i++) {
            if(_l.tokenIsStaked[_firstTokenId + i]) {
                revert LibKaijuCardsGen0Storage.TokenIsStaked(_firstTokenId + i);
            }
        }

        super._beforeTokenTransfer(_from, _to, _firstTokenId, _batchSize);
    }

    function _safeMint(address _to, uint256 _tokenId) internal virtual override(ERC721Upgradeable, NftBurnBridgingBase) {
        ERC721Upgradeable._safeMint(_to, _tokenId);
    }

    function getCharPrefixFromId(uint256 _tokenId) internal pure returns (string memory charPrefix_) {
        uint256 _charPrefixOffset = _tokenId / LibKaijuCardsGen0Storage.CHARACTER_TOKEN_OFFSET_AMOUNT;
        if(_charPrefixOffset == 1) {
            charPrefix_ = "bd";
        } else if(_charPrefixOffset == 2) {
            charPrefix_ = "bo";
        } else if(_charPrefixOffset == 3) {
            charPrefix_ = "bs";
        } else if(_charPrefixOffset == 4) {
            charPrefix_ = "bu";
        } else if(_charPrefixOffset == 5) {
            charPrefix_ = "fk";
        } else if(_charPrefixOffset == 6) {
            charPrefix_ = "fw";
        } else if(_charPrefixOffset == 7) {
            charPrefix_ = "gd";
        } else if(_charPrefixOffset == 8) {
            charPrefix_ = "gh";
        } else if(_charPrefixOffset == 9) {
            charPrefix_ = "gj";
        } else if(_charPrefixOffset == 10) {
            charPrefix_ = "gw";
        } else if(_charPrefixOffset == 11) {
            charPrefix_ = "je";
        } else if(_charPrefixOffset == 12) {
            charPrefix_ = "ll";
        } else if(_charPrefixOffset == 13) {
            charPrefix_ = "mf";
        } else if(_charPrefixOffset == 14) {
            charPrefix_ = "mgc";
        } else if(_charPrefixOffset == 15) {
            charPrefix_ = "mi";
        } else if(_charPrefixOffset == 16) {
            charPrefix_ = "nb";
        } else if(_charPrefixOffset == 17) {
            charPrefix_ = "ow";
        } else if(_charPrefixOffset == 18) {
            charPrefix_ = "pk";
        } else if(_charPrefixOffset == 19) {
            charPrefix_ = "sn";
        } else if(_charPrefixOffset == 20) {
            charPrefix_ = "sawo";
        } else if(_charPrefixOffset == 21) {
            charPrefix_ = "sw";
        } else if(_charPrefixOffset == 22) {
            charPrefix_ = "th";
        } else if(_charPrefixOffset == 23) {
            charPrefix_ = "tof";
        } else if(_charPrefixOffset == 24) {
            charPrefix_ = "wa";
        } else if(_charPrefixOffset == 25) {
            charPrefix_ = "wg";
        } else {
            revert LibKaijuCardsGen0Storage.UnknownTokenId(_tokenId);
        }
    }
}

