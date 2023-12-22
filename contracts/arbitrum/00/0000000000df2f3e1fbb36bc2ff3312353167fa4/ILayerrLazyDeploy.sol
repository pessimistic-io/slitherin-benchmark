// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {MintOrder} from "./MinterStructs.sol";

/**
 * @title ILayerrLazyDeploy
 * @author 0xth0mas (Layerr)
 * @notice ILayerrLazyDeploy interface defines functions required for
 *         lazy deployment/minting and gas refunds.
 */
interface ILayerrLazyDeploy {

    /// @dev Thrown when the deployment address does not match the expected deployment address
    error DeploymentFailed();
    /// @dev Thrown when a deployment fails and revertIfAlreadyDeployed is true
    error ContractAlreadyDeployed();
    /// @dev Thrown when a refund fails
    error RefundFailed();
    /// @dev Thrown when attempting to withdraw sponsored funds sent by another account
    error CallerNotSponsor();
    /// @dev Thrown when sponsor withdraw fails
    error SponsorshipWithdrawFailed();

    /// @dev Data used to calculate the refund amount for a gas sponsored transaction
    struct GasSponsorship {
        address sponsor;
        uint24 baseRefundUnits;
        uint24 baseRefundUnitsDeploy;
        uint24 baseRefundUnitsMint;
        bool refundDeploy;
        bool refundMint;
        uint64 maxRefundUnitsDeploy;
        uint64 maxRefundUnitsMint;
        uint64 maxBaseFee;
        uint64 maxPriorityFee;
        uint96 donationAmount;
        uint96 amountUsed;
        address additionalRefundCalculator;
        address balanceCheckAddress;
        uint96 minimumBalanceIncrement;
    }

    /// @dev Used for minting lazy deployed contracts with ERC20 tokens
    struct LazyERC20Payment {
        address tokenAddress;
        uint256 totalSpend;
    }

    /**
     * @notice Calculates the deployment address for a proxy contract with the provided
     *         `salt` and `constructorArgs`. Allows UX to determine what contract address
     *          should be used for signing mint parameters.
     * @param salt Random value used to generate unique deployment addresses for
     *             contracts with the same constructor arguments.
     * @param constructorArgs ABI encoded arguments to be passed to the contract constructor.
     * @return deploymentAddress The address the contract will be deployed to.
     */
    function findDeploymentAddress(
        bytes32 salt,
        bytes calldata constructorArgs
    ) external view returns(address deploymentAddress);

    /**
     * @notice Deploys a token contract and mints in the same transaction.
     * @param salt Random value used to generate unique deployment addresses for
     *             contracts with the same constructor arguments.
     * @param expectedDeploymentAddress The address the contract is expected to deploy at.
     *             The transaction will revert if this does not match the actual deployment
                   address.
     * @param constructorArgs ABI encoded arguments to be passed to the contract constructor.
     * @param mintOrders MintOrder array to be passed to the LayerrMinter contract after deployment
     * @param gasSponsorshipId If non-zero, gasSponsorshipId will be used to determine the parameters
     *                         for a gas refund.
     */
    function deployContractAndMint(
        bytes32 salt,
        address expectedDeploymentAddress,
        bytes calldata constructorArgs,
        MintOrder[] calldata mintOrders,
        uint256 gasSponsorshipId
    ) external payable;

    /**
     * @notice Deploys a token contract and mints in the same transaction with ERC20 tokens.
     * @param salt Random value used to generate unique deployment addresses for
     *             contracts with the same constructor arguments.
     * @param expectedDeploymentAddress The address the contract is expected to deploy at.
     *             The transaction will revert if this does not match the actual deployment
                   address.
     * @param constructorArgs ABI encoded arguments to be passed to the contract constructor.
     * @param mintOrders MintOrder array to be passed to the LayerrMinter contract after deployment
     * @param erc20Payments Array of items containing the ERC20 tokens to be pulled from caller for minting.
     * @param gasSponsorshipId If non-zero, gasSponsorshipId will be used to determine the parameters
     *                   for a gas refund.
     */
    function deployContractAndMintWithERC20(
        bytes32 salt,
        address expectedDeploymentAddress,
        bytes calldata constructorArgs,
        MintOrder[] calldata mintOrders,
        LazyERC20Payment[] calldata erc20Payments,
        uint256 gasSponsorshipId
    ) external payable;

    /**
     * @notice Deploys a token contract.
     * @param salt Random value used to generate unique deployment addresses for
     *             contracts with the same constructor arguments.
     * @param expectedDeploymentAddress The address the contract is expected to deploy at.
     *             The transaction will revert if this does not match the actual deployment
                   address.
     * @param constructorArgs ABI encoded arguments to be passed to the contract constructor.
     * @param gasSponsorshipId If non-zero, gasSponsorshipId will be used to determine the parameters
     *                         for a gas refund.
     */
    function deployContract(
        bytes32 salt,
        address expectedDeploymentAddress,
        bool revertIfAlreadyDeployed,
        bytes calldata constructorArgs,
        uint256 gasSponsorshipId
    ) external;

    /**
     * @notice Calls the LayerrMinter contract with `mintOrders` and processes a gas refund.
     * @param mintOrders MintOrder array to be passed to the LayerrMinter contract after deployment
     * @param gasSponsorshipId If non-zero, gasSponsorshipId will be used to determine the parameters
     *                         for a gas refund.
     */
    function mint(
        MintOrder[] calldata mintOrders,
        uint256 gasSponsorshipId
    ) external payable;

    /**
     * @notice Calls the LayerrMinter contract with `mintOrders` and ERC20 tokens and processes a gas refund.
     * @param mintOrders MintOrder array to be passed to the LayerrMinter contract after deployment
     * @param erc20Payments Array of items containing the ERC20 tokens to be pulled from caller for minting.
     * @param gasSponsorshipId If non-zero, gasSponsorshipId will be used to determine the parameters
     *                         for a gas refund.
     */
    function mintWithERC20(
        MintOrder[] calldata mintOrders,
        LazyERC20Payment[] calldata erc20Payments,
        uint256 gasSponsorshipId
    ) external payable;

    /**
     * @notice Provide a gas sponsorship for transactions deploying contracts or minting.
     * @param baseRefundUnits Base amount of gas units to use in a refund calculation
     * @param baseRefundUnitsDeploy Additional base amount of gas units to use for a deployment
     * @param baseRefundUnitsMint Additional base amount of gas units to use for minting
     * @param refundDeploy If true, deployment gas will be used to calculate a refund
     * @param refundMint If true, minting gas will be used to calculate a refund
     * @param maxRefundUnitsDeploy Maximum number of gas units that will be refunded for a deployment
     * @param maxRefundUnitsMint  Maximum number of gas units that will be refunded for a mint
     * @param maxBaseFee The max base fee to be used for gas refunds
     * @param maxPriorityFee The max priority fee to be used for gas refunds
     * @param additionalRefundCalculator If non-zero, an implementation of IAdditionalRefundCalculator
     *                                   to call to calculate an additional refund amount.
     * @param balanceCheckAddress If non-zero, an address to check for a native token balance increase 
     *                            from the mint transaction.
     * @param minimumBalanceIncrement The minimum amount the balance check address's balance needs to 
     *                                increase to allow the gas refund.
     */
    function sponsorGas(
        uint24 baseRefundUnits,
        uint24 baseRefundUnitsDeploy,
        uint24 baseRefundUnitsMint,
        bool refundDeploy,
        bool refundMint,
        uint64 maxRefundUnitsDeploy,
        uint64 maxRefundUnitsMint,
        uint64 maxBaseFee,
        uint64 maxPriorityFee,
        address additionalRefundCalculator,
        address balanceCheckAddress,
        uint96 minimumBalanceIncrement
    ) external payable;

    /**
     * @notice Callable by any address to add funds to a gas sponsorship
     * @param gasSponsorshipId The ID of the gas sponsorship to add funds to
     */
    function addToSponsorship(uint256 gasSponsorshipId) external payable;

    /**
     * @notice Callable by the gas sponsor to withdraw their sponsorship funds
     * @param gasSponsorshipId The ID of the gas sponsorship to withdraw
     */
    function withdrawSponsorship(uint256 gasSponsorshipId) external;
}
