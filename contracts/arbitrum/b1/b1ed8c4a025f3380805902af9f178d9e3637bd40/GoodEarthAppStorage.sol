// SPDX-License-Identifier: None
pragma solidity 0.8.18;
import {UsingDiamondOwner} from "./UsingDiamondOwner.sol";
import {LibDiamond} from "./LibDiamond.sol";

import "./EnumerableSet.sol";
import {LibAccessControl} from "./LibAccessControl.sol";
import {LibToken} from "./LibToken.sol";
import {IPayments} from "./IPayments.sol";
import {PaymentType} from "./IPayments.sol";

struct TokensConstants {
    string baseUri;
    string contractUri;
    uint256 nftActionPrice;
    address gen0ContractAddress;
    IPayments spellcasterPayments;
    address magicTokenAddress;
    address arbTokenAddress;
    uint256 battlePassUsdPrice;
}

struct TokensStorage {
    mapping(uint256 => bool) isTokenTradable;
    mapping(uint256 => address) ownerOf;
    bool mintingIsEnabled;
    bool tradingIsEnabled;
    address royaltiesRecipient;
    uint256 royaltiesPercentage;
    uint256 nftIndex;
    mapping(address => uint16) requestedNftActions; // mapping from requestor address to how many NFT conversions they have requested/paid for (ie. there's a flat fee for all)
    bool battlePassIsOpen;
    mapping(address => uint8) battlePassSeasonClaimed; // should be equal current battle pass season if it's claimed
    uint8 currentBattlePassSeason;
}

struct AccessControlStorage {
    bool paused;
    address contractFundsRecipient;
    mapping(address => EnumerableSet.UintSet) rolesByAddress;
}

library AppStorage {
    bytes32 public constant _TOKENS_STORAGE_POSITION =
        keccak256('kaijucards.storage.tokens');
    bytes32 public constant _TOKENS_CONSTANTS_POSITION =
        keccak256('kaijucards.constants.tokens');
    bytes32 public constant _ACCESS_CONTROL_STORAGE_POSITION =
        keccak256('kaijucards.storage.access_control');


    function tokensStorage() internal pure returns (TokensStorage storage ts) {
        bytes32 position = _TOKENS_STORAGE_POSITION;
        assembly {
            ts.slot := position
        }
    }

    function tokensConstants()
        internal
        pure
        returns (TokensConstants storage tc)
    {
        bytes32 position = _TOKENS_CONSTANTS_POSITION;
        assembly {
            tc.slot := position
        }
    }

    function accessControlStorage()
        internal
        pure
        returns (AccessControlStorage storage acs)
    {
        bytes32 position = _ACCESS_CONTROL_STORAGE_POSITION;
        assembly {
            acs.slot := position
        }
    }
}

contract WithStorage {
    function _token() internal pure returns (TokensStorage storage) {
        return AppStorage.tokensStorage();
    }

    function _constants() internal pure returns (TokensConstants storage) {
        return AppStorage.tokensConstants();
    }

    function _access() internal pure returns (AccessControlStorage storage) {
        return AppStorage.accessControlStorage();
    }
}

contract WithModifiers is WithStorage {
    using EnumerableSet for EnumerableSet.UintSet;

    modifier ownerOnly() {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(
            msg.sender == ds.contractOwner,
            'Only owner is allowed to perform this action'
        );
        _;
    }

    modifier internalOnly() {
        require(msg.sender == address(this), 'AppStorage: Not contract owner');
        _;
    }

    modifier roleOnly(LibAccessControl.Roles role) {
        require(
            _access().rolesByAddress[msg.sender].contains(uint256(role)) ||
                msg.sender == address(this),
            'Missing role'
        );
        _;
    }

    modifier pausable() {
        require(!_access().paused, 'Contract paused');
        _;
    }
}

