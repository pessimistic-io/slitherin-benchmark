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
import {JonesStrategyV3Base} from "./JonesStrategyV3Base.sol";
import {IStrategy} from "./IStrategy.sol";

contract JonesSSOVV3StrategyBase is JonesStrategyV3Base {
    using SafeERC20 for IERC20;
    using SsovV3Wrapper for ISsovV3;

    ISsovV3Viewer constant viewer =
        ISsovV3Viewer(0x8Ef275e05aB3c650927C5d4A5D6B7823233812be);

    /// SSOV contract
    ISsovV3 public SSOV;

    constructor(
        bytes32 _name,
        address _asset,
        address _SSOV,
        address _governor
    ) JonesStrategyV3Base(_name, _asset, _governor) {
        if (_SSOV == address(0)) {
            revert ADDRESS_CANNOT_BE_ZERO_ADDRESS();
        }
        SSOV = ISsovV3(_SSOV);
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
        SSOV.settleEpoch(address(this), _ssovEpoch, _ssovStrikes);
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
        SSOV.withdrawEpoch(_epoch, _strikes, address(this));
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
        _transferTokens(_to, _tokens, _shouldTransferEth);
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

