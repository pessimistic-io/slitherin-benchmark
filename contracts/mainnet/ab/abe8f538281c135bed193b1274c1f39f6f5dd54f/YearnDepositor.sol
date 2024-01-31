// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.11;
pragma abicoder v2;

import "./ZapDepositor.sol";
import "./IYearnVault.sol";

contract YearnDepositor is ZapDepositor {
    using SafeERC20Upgradeable for IERC20;

    /**
     * @notice Deposit a defined underling in the depositor protocol
     * @param _token the token to deposit
     * @param _underlyingAmount the amount to deposit
     * @return the amount ibt generated and sent back to the caller
     */
    function depositInProtocol(address _token, uint256 _underlyingAmount)
        public
        override
        onlyZaps
        tokenIsValid(_token)
        returns (uint256)
    {
        address yearnVault = IBTOfUnderlying[_token];

        IERC20(_token).transferFrom(
            msg.sender,
            address(this),
            _underlyingAmount
        ); // pull underlying tokens

        IYearnVault(yearnVault).deposit(uint256(_underlyingAmount)); // deposit underlying in the vault and mint IBTs to depositor.

        uint256 balanceOf_IBT = IYearnVault(yearnVault).balanceOf(
            address(this)
        );
        require(
            balanceOf_IBT <= _underlyingAmount,
            "YearnDepositor: balance error"
        );

        IYearnVault(yearnVault).transfer(msg.sender, balanceOf_IBT); // transfer IBT from depositor to Zap
        return balanceOf_IBT;
    }

    /**
     * @notice Deposit a defined underling in the depositor protocol from the caller adderss
     * @param _token the token to deposit
     * @param _underlyingAmount the amount to deposit
     * @param _from the address from which the underlying need to be pulled
     * @return the amount ibt generated
     */
    function depositInProtocolFrom(
        address _token,
        uint256 _underlyingAmount,
        address _from
    ) public override onlyZaps tokenIsValid(_token) returns (uint256) {
        address yearnVault = IBTOfUnderlying[_token];

        require(
            IERC20(_token).transferFrom(
                _from,
                address(this),
                _underlyingAmount
            ),
            "YearnDepositor: Underlying Pull failed"
        ); // pull underlying tokens

        IYearnVault(yearnVault).deposit(uint256(_underlyingAmount)); // deposit underlying in the vault and mint IBTs to depositor.

        uint256 balanceOf_IBT = IYearnVault(yearnVault).balanceOf(
            address(this)
        );
        require(
            balanceOf_IBT <= _underlyingAmount,
            "YearnDepositor: balance error"
        );

        IYearnVault(yearnVault).transfer(msg.sender, balanceOf_IBT); // transfer IBT from depositor to Zap
        return balanceOf_IBT;
    }
}

