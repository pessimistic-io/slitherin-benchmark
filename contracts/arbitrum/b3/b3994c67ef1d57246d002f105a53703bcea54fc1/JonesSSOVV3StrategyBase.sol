// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.10;

/**
 * Libraries
 */
import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {SsovV3Wrapper} from "./SsovV3Wrapper.sol";

/**
 * Interfaces
 */
import {ISsovV3} from "./ISsovV3.sol";
import {ISsovV3Viewer} from "./ISsovV3Viewer.sol";
import {IwETH} from "./IwETH.sol";
import {IUniswapV2Router02} from "./IUniswapV2Router02.sol";
import {ISsovV3Router} from "./ISsovV3Router.sol";
import {JonesStrategyV3Base} from "./JonesStrategyV3Base.sol";
import {IStrategy} from "./IStrategy.sol";

contract JonesSSOVV3StrategyBase is JonesStrategyV3Base {
    using SafeERC20 for IERC20;
    using SsovV3Wrapper for ISsovV3;

    IUniswapV2Router02 internal constant sushiRouter =
        IUniswapV2Router02(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);

    address public constant wETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    /// SSOV contract
    ISsovV3 public SSOV;

    /// SSOV Viewer contract
    ISsovV3Viewer public SSOVViewer;

    /// SSOV viewer
    ISsovV3Viewer public viewer;

    /// ssov v3 router
    ISsovV3Router public router;

    constructor(
        bytes32 _name,
        address _asset,
        address _SSOV,
        address _viewer,
        address _router,
        address _governor
    ) JonesStrategyV3Base(_name, _asset, _governor) {
        if (_SSOV == address(0)) {
            revert ADDRESS_CANNOT_BE_ZERO_ADDRESS();
        }

        if (_viewer == address(0)) {
            revert ADDRESS_CANNOT_BE_ZERO_ADDRESS();
        }

        if (_router == address(0)) {
            revert ADDRESS_CANNOT_BE_ZERO_ADDRESS();
        }

        SSOV = ISsovV3(_SSOV);
        viewer = ISsovV3Viewer(_viewer);
        router = ISsovV3Router(_router);
    }

    // ============================= Mutative functions ================================

    /**
     * Deposits funds to SSOV at desired strike price.
     * @param _strikeIndex Strike price index.
     * @param _amount Amount of collateral to deposit.
     * @return tokenId Token id of the deposit.
     */
    function depositSSOV(uint256 _strikeIndex, uint256 _amount)
        public
        onlyRole(KEEPER)
        returns (uint256 tokenId)
    {
        return SSOV.depositSSOV(_strikeIndex, _amount, address(this));
    }

    /**
     * Deposits funds to SSOV at multiple desired strike prices.
     * @param _strikeIndices Strike price indices.
     * @param _amounts Amounts of assets to deposit.
     * Returns a bool to indicate if the deposits went through successfully.
     */
    function depositSSOVMultiple(
        uint256[] memory _strikeIndices,
        uint256[] memory _amounts
    ) public onlyRole(KEEPER) returns (bool) {
        router.multideposit(_strikeIndices, _amounts, address(this), SSOV);
        return true;
    }

    /**
     * Buys options from Dopex SSOV.
     * @param _strikeIndex Strike index for current epoch.
     * @param _amount Amount of puts/calls to purchase.
     * Returns bool to indicate if put/call purchase went through sucessfully.
     */
    function purchaseOption(uint256 _strikeIndex, uint256 _amount)
        public
        onlyRole(KEEPER)
        returns (bool)
    {
        return SSOV.purchaseOption(_strikeIndex, _amount, address(this));
    }

    /**
     * @notice Settles the SSOV epoch.
     * @param _ssovEpoch The SSOV epoch to settle.
     * @param _ssovStrikes The SSOV strike indexes to settle.
     */
    function settleEpoch(uint256 _ssovEpoch, uint256[] memory _ssovStrikes)
        public
        onlyRole(KEEPER)
        returns (bool)
    {
        SSOV.settleEpoch(viewer, address(this), _ssovEpoch, _ssovStrikes);
        return true;
    }

    function withdrawTokenId(uint256 _tokenId)
        public
        onlyRole(KEEPER)
        returns (bool)
    {
        SSOV.withdraw(_tokenId, address(this));
        return true;
    }

    /**
     * @notice Withdraws from SSOV for the given `_epoch` and `_strikes`.
     * @param _epoch The SSOV epoch to withdraw from.
     * @param _strikes The SSOV strikes.
     */
    function withdrawEpoch(uint256 _epoch, uint256[] memory _strikes)
        public
        onlyRole(KEEPER)
        returns (bool)
    {
        SSOV.withdrawEpoch(viewer, _epoch, _strikes, address(this));
        return true;
    }

    // ============================= Management Functions ================================

    /**
     * @inheritdoc IStrategy
     */
    function migrateFunds(
        address _to,
        address[] memory _tokens,
        bool _shouldTransferEth,
        bool _shouldTransferERC721
    ) public virtual override onlyRole(GOVERNOR) {
        // transfer tokens
        for (uint256 i = 0; i < _tokens.length; i++) {
            IERC20 token = IERC20(_tokens[i]);
            uint256 assetBalance = token.balanceOf(address(this));
            if (assetBalance > 0) {
                token.safeTransfer(_to, assetBalance);
            }
            if (address(token) == asset) {
                totalDeposited = 0;
            }
        }

        // migrate ETH balance
        uint256 balanceGwei = address(this).balance;
        if (balanceGwei > 0 && _shouldTransferEth) {
            payable(_to).transfer(balanceGwei);
        }

        // withdraw erc721 tokens
        if (_shouldTransferERC721) {
            uint256[] memory depositTokens = viewer.walletOfOwner(
                address(this),
                SSOV
            );
            for (uint256 i = 0; i < depositTokens.length; i++) {
                uint256 tokenId = depositTokens[i];
                SSOV.safeTransferFrom(address(this), _to, tokenId);
            }
        }

        emit FundsMigrated(_to);
    }

    // ============================= ERC721 ================================
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return
            bytes4(
                keccak256("onERC721Received(address,address,uint256,bytes)")
            );
    }
}

