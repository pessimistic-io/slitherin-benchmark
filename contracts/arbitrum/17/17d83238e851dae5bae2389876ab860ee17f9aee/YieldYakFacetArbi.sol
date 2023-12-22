// SPDX-License-Identifier: BUSL-1.1
// Last deployed from commit: b5c62dcabdd9dc6577cb12be92681b37cadb26c9;
pragma solidity 0.8.17;

import "./IERC20Metadata.sol";
import "./Math.sol";
import "./TransferHelper.sol";

import "./ReentrancyGuardKeccak.sol";
import "./SolvencyMethods.sol";
import "./IYieldYak.sol";
import "./OnlyOwnerOrInsolvent.sol";

import {DiamondStorageLib} from "./DiamondStorageLib.sol";
import "./IWrappedNativeToken.sol";

// TODO: Check STATUS (tokenManager) of Vault tokens before allowing to stake
//This path is updated during deployment
import "./DeploymentConstants.sol";

contract YieldYakFacetArbi is ReentrancyGuardKeccak, SolvencyMethods, OnlyOwnerOrInsolvent {
    using TransferHelper for address payable;
    using TransferHelper for address;

    // Staking Vaults tokens
    address private constant YY_WOMBEX_USDT = 0x8Bc6968b7A9Eed1DD0A259eFa85dc2325B923dd2;
    address private constant YY_WOMBEX_USDCe = 0x4649c7c3316B27C4A3DB5f3B47f87C687776Eb8C;
    address private constant YY_WOMBEX_GLP = 0x28f37fa106AA2159c91C769f7AE415952D28b6ac;

    // Tokens
    address private constant USDT_TOKEN = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address private constant USDCe_TOKEN = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address private constant GLP_TOKEN = 0x5402B5F40310bDED796c7D0F3FF6683f5C0cFfdf;

    // ----- STAKE -----

    /**
       * Stakes USDT in Yield Yak protocol
       * @dev This function uses the redstone-evm-connector
       * @param amount amount of USDT to be staked
    **/
    function stakeUSDTYak(uint256 amount) public onlyOwner nonReentrant remainsSolvent {
        _stakeTokenYY(IYieldYak.YYStakingDetails({
            tokenAddress: USDT_TOKEN,
            vaultAddress: YY_WOMBEX_USDT,
            tokenSymbol: "USDT",
            vaultTokenSymbol: "YY_WOMBEX_USDT",
            amount: amount
        }));
    }

    /**
       * Stakes USDC.e in Yield Yak protocol
       * @dev This function uses the redstone-evm-connector
       * @param amount amount of USDC.e to be staked
    **/
    function stakeUSDCeYak(uint256 amount) public onlyOwner nonReentrant remainsSolvent {
        _stakeTokenYY(IYieldYak.YYStakingDetails({
            tokenAddress: USDCe_TOKEN,
            vaultAddress: YY_WOMBEX_USDCe,
            tokenSymbol: "USDC.e",
            vaultTokenSymbol: "YY_WOMBEX_USDC.e",
            amount: amount
        }));
    }

    /**
       * Stakes GLP in Yield Yak protocol
       * @dev This function uses the redstone-evm-connector
       * @param amount amount of GLP to be staked
    **/
    function stakeGLPYak(uint256 amount) public onlyOwner nonReentrant remainsSolvent {
        _stakeTokenYY(IYieldYak.YYStakingDetails({
        tokenAddress: GLP_TOKEN,
        vaultAddress: YY_WOMBEX_GLP,
        tokenSymbol: "GLP",
        vaultTokenSymbol: "YY_WOMBEX_GLP",
        amount: amount
        }));
    }

    // ----- UNSTAKE -----


    /**
    * Unstakes USDT from Yield Yak protocol
    * @dev This function uses the redstone-evm-connector
        * @param amount amount of USDT to be unstaked
    **/
    function unstakeUSDTYak(uint256 amount) public onlyOwnerOrInsolvent nonReentrant {
        _unstakeTokenYY(IYieldYak.YYStakingDetails({
        tokenAddress: USDT_TOKEN,
        vaultAddress: YY_WOMBEX_USDT,
        tokenSymbol: "USDT",
        vaultTokenSymbol: "YY_WOMBEX_USDT",
        amount: amount
        }));
    }

    /**
    * Unstakes USDC.e from Yield Yak protocol
    * @dev This function uses the redstone-evm-connector
        * @param amount amount of USDC.e to be unstaked
    **/
    function unstakeUSDCeYak(uint256 amount) public onlyOwnerOrInsolvent nonReentrant {
        _unstakeTokenYY(IYieldYak.YYStakingDetails({
            tokenAddress: USDCe_TOKEN,
            vaultAddress: YY_WOMBEX_USDCe,
            tokenSymbol: "USDC.e",
            vaultTokenSymbol: "YY_WOMBEX_USDC.e",
            amount: amount
        }));
    }

    /**
    * Unstakes GLP from Yield Yak protocol
    * @dev This function uses the redstone-evm-connector
        * @param amount amount of GLP to be unstaked
    **/
    function unstakeGLPYak(uint256 amount) public onlyOwnerOrInsolvent nonReentrant {
        _unstakeTokenYY(IYieldYak.YYStakingDetails({
        tokenAddress: GLP_TOKEN,
        vaultAddress: YY_WOMBEX_GLP,
        tokenSymbol: "GLP",
        vaultTokenSymbol: "YY_WOMBEX_GLP",
        amount: amount
        }));
    }

    // ----- PRIVATE METHODS -----

    /**
      * Stakes {stakingDetails.tokenAddress} token in the YieldYak protocol
      * @dev This function uses the redstone-evm-connector
      * @param stakingDetails IYieldYak.YYStakingDetails staking details
    **/
    function _stakeTokenYY(IYieldYak.YYStakingDetails memory stakingDetails) private recalculateAssetsExposure {
        ITokenManager tokenManager = DeploymentConstants.getTokenManager();
        IERC20Metadata yrtToken = IERC20Metadata(stakingDetails.vaultAddress);
        uint256 initialYRTBalance = yrtToken.balanceOf(address(this));

        stakingDetails.amount = Math.min(IERC20Metadata(stakingDetails.tokenAddress).balanceOf(address(this)), stakingDetails.amount);
        require(stakingDetails.amount > 0, "Cannot stake 0 tokens");
        // _ACTIVE = 2
        require(tokenManager.tokenToStatus(stakingDetails.tokenAddress) == 2, "Token not supported");
        require(tokenManager.tokenToStatus(stakingDetails.vaultAddress) == 2, "Vault token not supported");

        stakingDetails.tokenAddress.safeApprove(stakingDetails.vaultAddress, 0);
        stakingDetails.tokenAddress.safeApprove(stakingDetails.vaultAddress, stakingDetails.amount);
        IYieldYak(stakingDetails.vaultAddress).deposit(stakingDetails.amount);

        // Add/remove owned tokens
        DiamondStorageLib.addOwnedAsset(stakingDetails.vaultTokenSymbol, stakingDetails.vaultAddress);
        if(IERC20(stakingDetails.tokenAddress).balanceOf(address(this)) == 0) {
            DiamondStorageLib.removeOwnedAsset(stakingDetails.tokenSymbol);
        }

        emit Staked(
            msg.sender,
            stakingDetails.tokenSymbol,
            stakingDetails.vaultAddress,
            stakingDetails.amount,
            yrtToken.balanceOf(address(this)) - initialYRTBalance,
            block.timestamp);
    }

    /**
      * Unstakes {stakingDetails.tokenAddress} token in the YieldYak protocol
      * @dev This function uses the redstone-evm-connector
      * @param stakingDetails IYieldYak.YYStakingDetails staking details
    **/
    function _unstakeTokenYY(IYieldYak.YYStakingDetails memory stakingDetails) private recalculateAssetsExposure {
        IYieldYak vaultContract = IYieldYak(stakingDetails.vaultAddress);
        IERC20Metadata depositToken = IERC20Metadata(stakingDetails.tokenAddress);
        uint256 initialDepositTokenBalance = depositToken.balanceOf(address(this));
        stakingDetails.amount = Math.min(vaultContract.balanceOf(address(this)), stakingDetails.amount);

        vaultContract.withdraw(stakingDetails.amount);

        // Add/remove owned tokens
        DiamondStorageLib.addOwnedAsset(stakingDetails.tokenSymbol, stakingDetails.tokenAddress);
        if(vaultContract.balanceOf(address(this)) == 0) {
            DiamondStorageLib.removeOwnedAsset(stakingDetails.vaultTokenSymbol);
        }

        emit Unstaked(
            msg.sender,
            stakingDetails.tokenSymbol,
            stakingDetails.vaultAddress,
            depositToken.balanceOf(address(this)) - initialDepositTokenBalance,
            stakingDetails.amount,
            block.timestamp);
    }


    modifier onlyOwner() {
        DiamondStorageLib.enforceIsContractOwner();
        _;
    }

    /* ========== RECEIVE AVAX FUNCTION ========== */
    receive() external payable {}

    /**
        * @dev emitted when user stakes an asset
        * @param user the address executing staking
        * @param asset the asset that was staked
        * @param vault address of the vault token
        * @param depositTokenAmount how much of deposit token was staked
        * @param receiptTokenAmount how much of receipt token was received
        * @param timestamp of staking
    **/
    event Staked(address indexed user, bytes32 indexed asset, address indexed vault, uint256 depositTokenAmount, uint256 receiptTokenAmount, uint256 timestamp);

    /**
        * @dev emitted when user unstakes an asset
        * @param user the address executing unstaking
        * @param vault address of the vault token
        * @param asset the asset that was unstaked
        * @param depositTokenAmount how much deposit token was received
        * @param receiptTokenAmount how much receipt token was unstaked
        * @param timestamp of unstaking
    **/
    event Unstaked(address indexed user, bytes32 indexed asset, address indexed vault, uint256 depositTokenAmount, uint256 receiptTokenAmount, uint256 timestamp);
}
