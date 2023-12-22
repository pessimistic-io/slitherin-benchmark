// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./console.sol";
import {NotionalERC20} from "./NotionalERC20.sol";
import {ILiabilityToken} from "./ILiabilityToken.sol";
import {Errors} from "./Errors.sol";
import {VersionedInitializable} from "./VersionedInitializable.sol";
import {IERC20} from "./IERC20.sol";
import {IGuild} from "./IGuild.sol";
import {INotionalERC20} from "./INotionalERC20.sol";
import {IInitializableLiabilityToken} from "./IInitializableLiabilityToken.sol";
import {UpgradeableERC20} from "./UpgradeableERC20.sol";
import {CreditDelegation} from "./CreditDelegation.sol";
import {ICreditDelegation} from "./ICreditDelegation.sol";
import {WadRayMath} from "./WadRayMath.sol";

/**
 * @title TAZZ ERC20 LiabilityToken
 * @author Tazz Labs
 * @notice Implementation of the perpetual debt liability token
 */
contract LiabilityToken is VersionedInitializable, CreditDelegation, NotionalERC20, ILiabilityToken {
    uint256 public constant LIABILITY_TOKEN_REVISION = 0x1;

    /// @inheritdoc VersionedInitializable
    function getRevision() internal pure virtual override returns (uint256) {
        return LIABILITY_TOKEN_REVISION;
    }

    /**
     * @dev Constructor.
     * @param guild_ The address of the Guild contract
     **/
    constructor(IGuild guild_) NotionalERC20(guild_, 'DTOKEN_IMPL', 'DTOKEN_IMPL', 0) {
        // Intentionally left blank
    }

    // / @inheritdoc IInitializableLiabilityToken
    function initialize(
        IGuild initializingGuild,
        uint8 dTokenDecimals,
        string calldata dTokenName,
        string calldata dTokenSymbol,
        bytes calldata params
    ) external override initializer {
        require(initializingGuild == GUILD, Errors.GUILD_ADDRESSES_DO_NOT_MATCH);
        _name = string.concat('d', dTokenName);
        _symbol = string.concat('d', dTokenSymbol);
        _decimals = dTokenDecimals;
        _nFactor = WadRayMath.RAY;

        emit Initialized(address(GUILD), dTokenDecimals, dTokenName, dTokenSymbol, params);
    }

    function mint(
        address user,
        address onBehalfOf,
        uint256 amount
    ) public onlyGuild {
        if (user != onBehalfOf) {
            require(_borrowAllowances[onBehalfOf][user] >= amount, Errors.INSUFFICIENT_CREDIT_DELEGATION);
            _decreaseBorrowAllowance(onBehalfOf, user, amount);
        }
        _mint(onBehalfOf, amount);
        emit Mint(user, onBehalfOf, amount);
    }

    function burn(address account, uint256 amount) public onlyGuild {
        _burn(account, amount);
    }

    function updateNotionalFactor(uint256 multFactor) external onlyGuild returns (uint256) {
        return _updateNotionalFactor(multFactor);
    }

    /**
     * @dev Being non transferrable, the debt token does not implement any of the
     * standard ERC20 functions for transfer and allowance.
     **/
    function transfer(address, uint256) public virtual override(UpgradeableERC20, IERC20) returns (bool) {
        revert(Errors.OPERATION_NOT_SUPPORTED);
    }

    function allowance(address, address) public view virtual override(UpgradeableERC20, IERC20) returns (uint256) {
        revert(Errors.OPERATION_NOT_SUPPORTED);
    }

    function approve(address, uint256) public virtual override(UpgradeableERC20, IERC20) returns (bool) {
        revert(Errors.OPERATION_NOT_SUPPORTED);
    }

    function transferFrom(
        address,
        address,
        uint256
    ) public virtual override(UpgradeableERC20, IERC20) returns (bool) {
        revert(Errors.OPERATION_NOT_SUPPORTED);
    }

    function increaseAllowance(address, uint256) public virtual override returns (bool) {
        revert(Errors.OPERATION_NOT_SUPPORTED);
    }

    function decreaseAllowance(address, uint256) public virtual override returns (bool) {
        revert(Errors.OPERATION_NOT_SUPPORTED);
    }
}

