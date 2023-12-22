// SPDX-License-Identifier: NONE
pragma solidity 0.8.10;
import "./console.sol";
import {UsingDiamondOwner} from "./UsingDiamondOwner.sol";
import {LibDiamond} from "./LibDiamond.sol";
import {LibMeta} from "./LibMeta.sol";
import {LibAccessControl} from "./LibAccessControl.sol";

import {EnumerableSet} from "./EnumerableSet.sol";

struct ShopStorage {
    // Cost to purchase a foundersPack (x1000 for precision)
    uint32 foundersPackUsdCost;
    uint256 foundersPackGasOffset;
    mapping(address => bool) purchasedFoundersPackByAddress;
    uint256 purchasedFoundersPacksCount;
    bool foundersPackPurchaseAllowed;
    uint256 botsFeePercentage;
}

struct PriceStorage {
    // Native token price in USD (x1000 for precision)
    uint256 nativeTokenPriceInUsd;
}

struct GameStorage {
    mapping(address => uint128) rolesByAddress;
}

struct TokensStorage {
    address royaltiesRecipient;
    uint16 totalMintedEggs;
    uint256 royaltiesPercentage;
    uint256 eggsIndex;
    uint256 nftsIndex;
    uint256 seedPetsIndex;
    uint256 resourcesIndex;
    uint256 fungiblesIndex;
    uint256 withdrawalGasOffset;
    mapping(string => bool) usedCharacterNames;
    mapping(string => bool) pendingWithdrawalByApiId;
    mapping(uint256 => bool) isTokenLocked;
    mapping(uint256 => bool) mintedByMintId;
    mapping(uint256 => address) ownerOf;
}

struct TokensConstants {
    string gen0EggUri;
    string baseUri;
    string contractUri;
}

struct AccessControlStorage {
    bool paused;
    address contractFundsRecipient;
    address forgerAddress;
    address borisAddress;
    mapping(address => EnumerableSet.UintSet) rolesByAddress;
}

library LibStorage {
    bytes32 public constant _SHOP_STORAGE_POSITION =
        keccak256("thebeacon.storage.shop");
    bytes32 public constant _PRICE_STORAGE_POSITION =
        keccak256("thebeacon.storage.price");
    bytes32 public constant _TOKENS_STORAGE_POSITION =
        keccak256("thebeacon.storage.tokens");
    bytes32 public constant _TOKENS_CONSTANTS_POSITION =
        keccak256("thebeacon.constants.tokens");
    bytes32 public constant _ACCESS_CONTROL_STORAGE_POSITION =
        keccak256("thebeacon.storage.access_control");

    function shopStorage() internal pure returns (ShopStorage storage ss) {
        bytes32 position = _SHOP_STORAGE_POSITION;
        assembly {
            ss.slot := position
        }
    }

    function priceStorage() internal pure returns (PriceStorage storage ps) {
        bytes32 position = _PRICE_STORAGE_POSITION;
        assembly {
            ps.slot := position
        }
    }

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
    function _ss() internal pure returns (ShopStorage storage) {
        return LibStorage.shopStorage();
    }

    function _ps() internal pure returns (PriceStorage storage) {
        return LibStorage.priceStorage();
    }

    function _ts() internal pure returns (TokensStorage storage) {
        return LibStorage.tokensStorage();
    }

    function _tc() internal pure returns (TokensConstants storage) {
        return LibStorage.tokensConstants();
    }

    function _acs() internal pure returns (AccessControlStorage storage) {
        return LibStorage.accessControlStorage();
    }
}

contract WithModifiers is WithStorage {
    using EnumerableSet for EnumerableSet.UintSet;

    modifier ownerOnly() {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(
            msg.sender == ds.contractOwner,
            "Only owner is allowed to perform this action"
        );
        _;
    }

    modifier internalOnly() {
        require(msg.sender == address(this), "LibStorage: Not contract owner");
        _;
    }

    modifier roleOnly(LibAccessControl.Roles role) {
        require(
            _acs().rolesByAddress[msg.sender].contains(uint256(role)) ||
                msg.sender == address(this),
            "Missing role"
        );
        _;
    }

    modifier pausable() {
        require(!_acs().paused, "Contract paused");
        _;
    }
}

