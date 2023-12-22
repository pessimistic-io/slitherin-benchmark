// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;
import {AccessControl} from "./AccessControl.sol";
import "./Ownable.sol";
import "./Initializable.sol";

contract AcUpgradable is AccessControl, Ownable, Initializable {
    // 0xcb58d6d985142a614029cdf01861b4fe094d5919a47e69b8310dc4093d9d6ad0
    bytes32 internal constant ROLE_CONTROLLER = keccak256("ROLE_CONTROLLER");
    // 0x241ecf16d79d0f8dbfb92cbc07fe17840425976cf0667f022fe9877caa831b08
    bytes32 internal constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    // 0xfb248bbb6ca5a799a6bb9ba79f58aa5cdbe0e5979238a967315e7ffbfd119d1a
    bytes32 internal constant ROLE_POS_KEEPER = keccak256("ROLE_POS_KEEPER");
    //======================
    // 0x5d8e12c39142ff96d79d04d15d1ba1269e4fe57bb9d26f43523628b34ba108ec
    bytes32 internal constant WITHDRAW_ROLE = keccak256("WITHDRAW_ROLE");
    //======================
    // 0x8d1089725c0dc266707fa6207730fb801dcd03108bfed7a21099bd303651d2b7
    bytes32 internal constant MARKET_MGR_ROLE = keccak256("MARKET_MGR_ROLE");
    // 0x275a642cf55cb12407e505ec86398168f240e88df6e66d1649bd09de9071c5db
    bytes32 internal constant GLOBAL_MGR_ROLE = keccak256("GLOBAL_MGR_ROLE");

    // 0xcb6bc1c12dd43bca8d7dd46d975f913325437d0dcd5978e99d515e4ad39b9772
    bytes32 internal constant VAULT_MGR_ROLE = keccak256("VAULT_MGR_ROLE");
    
    // 0x92de27771f92d6942691d73358b3a4673e4880de8356f8f2cf452be87e02d363
    bytes32 internal constant FREEZER_ROLE = keccak256("FREEZER_ROLE");

    // 0x59c7a9ef9a56707d87d116a5d27496afee2604c70b902ac2c4dbdcb68f36f2ea
    bytes32 internal constant FEE_DISTRIBUTOR_ROLE =
        keccak256("FEE_DISTRIBUTOR_ROLE");
    // 0xf21b97e3e053faeacb5e76d16d9daf713b69d060518bccb2c9ee13a7f9cfc49f
    bytes32 internal constant FEE_MGR_ROLE = keccak256("FEE_MGR_ROLE");
    // 0xf7650eb8b2f3fb3c9b995a8ee2fc3c04ed07f1c4efe01998177b109698c67517
    bytes32 internal constant PRICE_UPDATE_ROLE =
        keccak256("PRICE_UPDATE_ROLE");

    // 0xde57aa0116fb656e0ab30962f03bb7a49dccfb8fac7bf6a5cf94d0d56d0e7337
    bytes32 internal constant MULTI_SIGN_ROLE = keccak256("MULTI_SIGN_ROLE");

    uint256 private initBlock;

    modifier onlyInitOr(bytes32 _role) {
        bool isDefaultAdmin = hasRole(DEFAULT_ADMIN_ROLE, _msgSender());
        if (isDefaultAdmin) {
            if (block.timestamp - initBlock >= 3600 * 24)
                revert("ac time passed");
        } else {
            _checkRole(_role, _msgSender());
        }
        _;
    }

    function _initialize(address _f) internal {
        initBlock = block.timestamp;
        _transferOwnership(_msgSender());

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(DEFAULT_ADMIN_ROLE, _f);
    }

    function transferAdmin(address to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setupRole(DEFAULT_ADMIN_ROLE, to);
        _transferOwnership(to);
        _revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    modifier onlyAdmin() {
        _checkRole(MANAGER_ROLE);
        _;
    }

    modifier onlyFreezer() {
        _checkRole(FREEZER_ROLE);
        _;
    }

    modifier onlyPositionKeeper() {
        _checkRole(ROLE_POS_KEEPER);
        _;
    }

    modifier onlyController() {
        _checkRole(ROLE_CONTROLLER);
        _;
    }

    modifier onlyUpdater() {
        require(hasRole(PRICE_UPDATE_ROLE, msg.sender));
        _;
    }

    function grantControllerRoleByMarketManager(
        address _account
    ) external onlyRole(MARKET_MGR_ROLE) {
        require(supportMarketRoleGrantControllerRole());
        _grantRole(ROLE_CONTROLLER, _account);
    }

    function supportMarketRoleGrantControllerRole()
        internal
        pure
        virtual
        returns (bool)
    {
        return false;
    }
}

