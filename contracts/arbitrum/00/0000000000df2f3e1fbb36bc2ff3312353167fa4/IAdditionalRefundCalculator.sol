// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

/**
 * @title IAdditionalRefundCalculator
 * @author 0xth0mas (Layerr)
 * @notice IAdditionalRefundCalculator interface defines functions required for
 *         providing additional refund amounts in lazy deploys/mints.
 *         This can be implemented to provide refunds for rollup transaction fees
 *         or to pay refunds for any sort of transaction at the discretion of the 
 *         gas sponsor.
 */
interface IAdditionalRefundCalculator {

    /**
     * @notice Allows an external gas refund calculator to perform additional
     *         checks prior to deployment and minting transactions being processed
     *         to validate the gas refund amount the sponsor is going to provide.
     */
    function additionalRefundPrecheck() external;

    /**
     * @notice Called from LayerrLazyDeploy to calculate an additional refund 
     *         for a deploy or mint transaction that is being gas sponsored.
     *         The IAdditionalRefundCalculator implementation address is defined
     *         by the gas sponsor and refunds out of the amount deposited to
     *         LayerrLazyDeploy.
     * @param caller Address of the account that is calling LayerrLazyDeploy
     * @param calldataLength The length of calldata sent to LayerrLazyDeploy
     * @param gasUsedDeploy The amount of gas used for deployment
     * @param gasUsedMint The amount of gas used for minting
     * @return additionalRefundAmount The amount of native token to add to a refund
     */
    function calculateAdditionalRefundAmount(
        address caller,
        uint256 calldataLength,
        uint256 gasUsedDeploy,
        uint256 gasUsedMint
    ) external view returns(uint256 additionalRefundAmount);
}
