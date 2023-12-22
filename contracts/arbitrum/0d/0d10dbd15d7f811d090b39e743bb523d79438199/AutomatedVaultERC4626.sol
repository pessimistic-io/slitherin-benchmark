// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

/**
 * @title   Automated ERC-4626 Vault Factory.
 * @author  André Ferreira
 * @notice  See the following for the full EIP-4626 specification https://eips.ethereum.org/EIPS/eip-4626.
 * @notice  See the following for the full EIP-4626 openzeppelin implementation https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC4626.sol.

  * @dev    VERSION: 1.0
 *          DATE:    2023.08.13
*/

import {Enums} from "./Enums.sol";
import {ConfigTypes} from "./ConfigTypes.sol";
import {Math} from "./Math.sol";
import {PercentageMath} from "./percentageMath.sol";
import {IAutomatedVaultERC4626} from "./IAutomatedVaultERC4626.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {ERC4626, IERC4626} from "./ERC4626.sol";
import {IERC20Metadata, IERC20, ERC20} from "./ERC20.sol";

contract AutomatedVaultERC4626 is ERC4626, IAutomatedVaultERC4626 {
    using Math for uint256;
    using PercentageMath for uint256;
    using SafeERC20 for IERC20;
    ConfigTypes.InitMultiAssetVaultParams public initMultiAssetVaultParams;
    ConfigTypes.StrategyParams public strategyParams;

    uint8 public constant MAX_NUMBER_OF_BUY_ASSETS = 10;

    address[] public buyAssetAddresses;
    uint8[] public buyAssetsDecimals;
    uint256 public buyAssetsLength;
    uint256 public lastUpdate;
    address[] public allDepositorAddresses;
    uint256 public allDepositorsLength;

    event CreatorFeeTransfered(
        address indexed vault,
        address indexed depositor,
        address indexed creator,
        uint256 shares
    );

    /**
     * @dev Attempted to deposit more assets than the max amount for `receiver`.
     */
    error ERC4626ExceededMaxDeposit(
        address receiver,
        uint256 assets,
        uint256 max
    );

    /**
     * @dev Underlying asset contracts must be ERC20-compatible contracts (ERC20 or ERC777) whitelisted at factory level.
     */
    constructor(
        ConfigTypes.InitMultiAssetVaultParams memory _initMultiAssetVaultParams,
        ConfigTypes.StrategyParams memory _strategyParams
    )
        ERC4626(_initMultiAssetVaultParams.depositAsset)
        ERC20(
            _initMultiAssetVaultParams.name,
            _initMultiAssetVaultParams.symbol
        )
    {
        require(msg.sender == _initMultiAssetVaultParams.factory, "FORBIDDEN");
        _validateInputs(
            _initMultiAssetVaultParams.buyAssets,
            _strategyParams.buyAmounts
        );
        initMultiAssetVaultParams = _initMultiAssetVaultParams;
        _populateBuyAssetsData(_initMultiAssetVaultParams);
        strategyParams = _strategyParams;
        _setBuyAssetsDecimals(_initMultiAssetVaultParams.buyAssets);
        initMultiAssetVaultParams.isActive = false;
    }

    modifier onlyStrategyWorker() {
        require(
            msg.sender == strategyParams.strategyWorker,
            "Only StrategyWorker can call this"
        );
        _;
    }

    /** @dev See {IERC4626-deposit}. */
    function deposit(
        uint256 assets,
        address receiver
    ) public override(ERC4626, IERC4626) returns (uint256) {
        uint256 maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
        }

        uint256 shares = previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, shares);
        return shares;
    }

    function setLastUpdate() public onlyStrategyWorker {
        lastUpdate = block.timestamp;
    }

    function getInitMultiAssetVaultParams()
        public
        view
        returns (ConfigTypes.InitMultiAssetVaultParams memory)
    {
        return initMultiAssetVaultParams;
    }

    function getBuyAssetAddresses() public view returns (address[] memory) {
        return buyAssetAddresses;
    }

    function getStrategyParams()
        public
        view
        returns (ConfigTypes.StrategyParams memory)
    {
        return strategyParams;
    }

    function _validateInputs(
        IERC20[] memory buyAssets,
        uint256[] memory buyAmounts
    ) private pure {
        // Check if max number of deposited assets was not exceeded
        require(
            buyAssets.length <= uint256(MAX_NUMBER_OF_BUY_ASSETS),
            "MAX_NUMBER_OF_BUY_ASSETS exceeded"
        );
        // Check if both arrays have the same length
        require(
            buyAmounts.length == buyAssets.length,
            "buyAmounts and buyAssets arrays must have the same length"
        );
    }

    function _setBuyAssetsDecimals(IERC20[] memory buyAssets) private {
        for (uint8 i = 0; i < buyAssets.length; i++) {
            buyAssetsDecimals.push(_getAssetDecimals(buyAssets[i]));
        }
    }

    function _getAssetDecimals(
        IERC20 depositAsset
    ) private view returns (uint8) {
        (bool success, uint8 assetDecimals) = _originalTryGetAssetDecimals(
            depositAsset
        );
        uint8 finalAssetDecimals = success ? assetDecimals : 18;
        return finalAssetDecimals;
    }

    function _populateBuyAssetsData(
        ConfigTypes.InitMultiAssetVaultParams memory _initMultiAssetVaultParams
    ) private {
        buyAssetsLength = _initMultiAssetVaultParams.buyAssets.length;
        for (uint256 i = 0; i < buyAssetsLength; i++) {
            buyAssetAddresses.push(
                address(_initMultiAssetVaultParams.buyAssets[i])
            );
        }
    }

    /**
     * @dev Attempts to fetch the asset decimals. A return value of false indicates that the attempt failed in some way.
     */
    function _originalTryGetAssetDecimals(
        IERC20 asset_
    ) private view returns (bool, uint8) {
        (bool success, bytes memory encodedDecimals) = address(asset_)
            .staticcall(abi.encodeCall(IERC20Metadata.decimals, ()));
        if (success && encodedDecimals.length >= 32) {
            uint256 returnedDecimals = abi.decode(encodedDecimals, (uint256));
            if (returnedDecimals <= type(uint8).max) {
                return (true, uint8(returnedDecimals));
            }
        }
        return (false, 0);
    }

    /**
     * @dev Deposit/mint common workflow.
     */
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        // **************************************** ERC4262 ****************************************
        // If _asset is ERC777, `transferFrom` can trigger a reentrancy BEFORE the transfer happens through the
        // `tokensToSend` hook. On the other hand, the `tokenReceived` hook, that is triggered after the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer before we mint so that any reentrancy would happen before the
        // assets are transferred and before the shares are minted, which is a valid state.
        // slither-disable-next-line reentrancy-no-eth
        // **************************************** CUSTOM ****************************************
        // After underlying transfer and before vault lp mint _afterUnderlyingTransferHook was added
        // where vault creator fee logic is implemented
        address depositAsset = asset();
        SafeERC20.safeTransferFrom(
            IERC20(depositAsset),
            caller,
            address(this),
            assets
        );
        _afterUnderlyingTransferHook(receiver, shares);
        emit Deposit(caller, receiver, assets, shares);
    }

    function _afterUnderlyingTransferHook(
        address receiver,
        uint256 shares
    ) internal {
        if (receiver == initMultiAssetVaultParams.creator) {
            if (balanceOf(receiver) == 0) {
                allDepositorAddresses.push(receiver);
                allDepositorsLength += 1;
            }
            _mint(receiver, shares);
        } else {
            // if deposit is not from vault creator, a fee will be removed
            // from depositor and added to creator balance
            uint256 creatorPercentage = initMultiAssetVaultParams
                .creatorPercentageFeeOnDeposit;
            uint256 depositorPercentage = PercentageMath.PERCENTAGE_FACTOR -
                creatorPercentage;
            uint256 creatorShares = shares.percentMul(creatorPercentage);
            uint256 depositorShares = shares.percentMul(depositorPercentage);

            emit CreatorFeeTransfered(
                address(this),
                initMultiAssetVaultParams.creator,
                receiver,
                creatorShares
            );

            if (balanceOf(receiver) == 0) {
                allDepositorAddresses.push(receiver);
                allDepositorsLength += 1;
            }
            _mint(receiver, depositorShares);

            if (balanceOf(initMultiAssetVaultParams.creator) == 0) {
                allDepositorAddresses.push(initMultiAssetVaultParams.creator);
                allDepositorsLength += 1;
            }
            _mint(initMultiAssetVaultParams.creator, creatorShares);
        }
        // Activates vault after 1st deposit
        if (initMultiAssetVaultParams.isActive == false) {
            initMultiAssetVaultParams.isActive = true;
        }
    }
}

