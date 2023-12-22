// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Pausable.sol";
import "./SafeERC20.sol";
import {IAddressesRegistry} from "./IAddressesRegistry.sol";
import {Errors} from "./Errors.sol";
import {ILPTokenSVS} from "./ILPTokenSVS.sol";
import {IVault1155} from "./IVault1155.sol";
import {ISVS} from "./ISVS.sol";
import {ISVSCollectionConnector} from "./ISVSCollectionConnector.sol";

/**
 * @title LPTokenSVS
 * @author Souq.Finance
 * @notice The LP Token contract of each svs liquidity pool
 * @notice License: https://souq-exchange.s3.amazonaws.com/LICENSE.md
 */
contract LPTokenSVS is ILPTokenSVS, ERC20, ERC20Burnable, Pausable {
    using SafeERC20 for IERC20;
    IAddressesRegistry internal immutable addressesRegistry;
    address public immutable pool;
    uint8 public immutable tokenDecimals;

    constructor(
        address _pool,
        address registry,
        address[] memory tokens,
        string memory _symbol,
        string memory _name,
        uint8 _decimals
    ) ERC20(_name, _symbol) {
        require(_pool != address(0), Errors.ADDRESS_IS_ZERO);
        require(registry != address(0), Errors.ADDRESS_IS_ZERO);
        tokenDecimals = _decimals;
        pool = _pool;
        addressesRegistry = IAddressesRegistry(registry);
        for (uint256 i = 0; i < tokens.length; ++i) {
            ISVS(IVault1155(tokens[i]).getSVS()).setApprovalForAll(address(pool), true);
        }
    }

    /**
     * @dev modifier for when the the msg sender is the liquidity pool that created it only
     */
    modifier onlyPool() {
        require(_msgSender() == address(pool), Errors.CALLER_MUST_BE_POOL);
        _;
    }

    /**
     * @dev Returns the number of decimals for this token. Public due to override.
     * @return uint8 the number of decimals
     */
    function decimals() public view override(ERC20,ILPTokenSVS) returns (uint8) {
        return tokenDecimals;
    }

    /// @inheritdoc ILPTokenSVS
    function getTotal() external view returns (uint256) {
        return totalSupply();
    }

    /// @inheritdoc ILPTokenSVS
    function getBalanceOf(address account) external view returns (uint256) {
        return balanceOf(account);
    }

    /// @inheritdoc ILPTokenSVS
    function pause() external onlyPool {
        //_pause already emits an event
        _pause();
    }

    /// @inheritdoc ILPTokenSVS
    function unpause() external onlyPool {
        //_unpause already emits an event
        _unpause();
    }

    /// @inheritdoc ILPTokenSVS
    function checkPaused() external view returns (bool) {
        return paused();
    }

    /// @inheritdoc ILPTokenSVS
    function setApproval20(address token, uint256 amount) external onlyPool {
        bool returnApproved = IERC20(token).approve(pool, amount);
        require(returnApproved, Errors.APPROVAL_FAILED);
    }

    /// @inheritdoc ILPTokenSVS
    function checkApproval1155(address[] memory tokens) external onlyPool
    {
        for (uint256 i = 0; i < tokens.length; ++i) {
            if(!ISVS(IVault1155(tokens[i]).getSVS()).isApprovedForAll(address(this),address(pool)))
            ISVS(IVault1155(tokens[i]).getSVS()).setApprovalForAll(address(pool), true);
        }
    }

    /// @inheritdoc ILPTokenSVS
    function mint(address to, uint256 amount) external onlyPool {
        //_mint already emits a transfer event
        _mint(to, amount);
    }

    /// @inheritdoc ILPTokenSVS
    function burn(address from, uint256 amount) external onlyPool {
        //_burn already emits a transfer event
        _burn(from, amount);
    }

    /// @inheritdoc ILPTokenSVS
    function rescueTokens(address token, uint256 amount, address receiver) external onlyPool {
        //event emitted in the pool logic library
        IERC20(token).safeTransfer(receiver, amount);
    }

    /**
     * @dev Implementation of the ERC1155 token received hook.
     */
    function onERC1155Received(address, address, uint256, uint256, bytes memory) external virtual returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    /**
     * @dev Implementation of the ERC1155 batch token received hook.
     */
    function onERC1155BatchReceived(address, address, uint256[] memory, uint256[] memory, bytes memory) external virtual returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    /// @inheritdoc ILPTokenSVS
    function redeemShares(address collection, uint256 id, uint256 amount) external onlyPool {
        IVault1155(collection).redeemUnderlying(amount, id);
    }
}
