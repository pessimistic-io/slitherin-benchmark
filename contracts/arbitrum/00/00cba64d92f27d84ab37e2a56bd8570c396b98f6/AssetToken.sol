// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {NotionalERC20} from "./NotionalERC20.sol";
import {IAssetToken} from "./IAssetToken.sol";
import {Errors} from "./Errors.sol";
import {VersionedInitializable} from "./VersionedInitializable.sol";
import {IERC20} from "./IERC20.sol";
import {IGuild} from "./IGuild.sol";
import {IInitializableAssetToken} from "./IInitializableAssetToken.sol";
import {WadRayMath} from "./WadRayMath.sol";

/**
 * @title TAZZ ERC20 AssetToken
 * @author Tazz Labs
 * @notice Implementation of the perpetual debt asset token
 */
contract AssetToken is VersionedInitializable, NotionalERC20, IAssetToken {
    uint256 public constant ASSET_TOKEN_REVISION = 0x1;

    /// @inheritdoc VersionedInitializable
    function getRevision() internal pure virtual override returns (uint256) {
        return ASSET_TOKEN_REVISION;
    }

    /**
     * @dev Constructor.
     * @param guild_ The address of the Guild contract
     **/
    constructor(IGuild guild_) NotionalERC20(guild_, 'ZTOKEN_IMPL', 'ZTOKEN_IMPL', 0) {
        // Intentionally left blank
    }

    /// @inheritdoc IInitializableAssetToken
    function initialize(
        IGuild initializingGuild,
        uint8 zTokenDecimals,
        string calldata zTokenName,
        string calldata zTokenSymbol,
        bytes calldata params
    ) external override initializer {
        require(initializingGuild == GUILD, Errors.GUILD_ADDRESSES_DO_NOT_MATCH);
        _name = string.concat('z', zTokenName);
        _symbol = string.concat('z', zTokenSymbol);
        _decimals = zTokenDecimals;
        _nFactor = WadRayMath.RAY;

        emit Initialized(address(GUILD), zTokenDecimals, zTokenName, zTokenSymbol, params);
    }

    function mint(address account, uint256 amount) external virtual override onlyGuild {
        return _mint(account, amount);
    }

    function burn(address account, uint256 amount) public onlyGuild {
        return _burn(account, amount);
    }

    function updateNotionalFactor(uint256 multFactor) external onlyGuild returns (uint256) {
        return _updateNotionalFactor(multFactor);
    }
}

