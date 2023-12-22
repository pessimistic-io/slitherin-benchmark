// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.21;

import "./SafeERC20.sol";
import "./Pausable.sol";
import "./Address.sol";
import {FactoryContract} from "./IFactory.sol";
import {TreasuryContract} from "./ITreasury.sol";
import {VaultFeeHandler} from "./VaultFeeHandler.sol";

contract Vault is Context, Pausable, VaultFeeHandler {
    using SafeERC20 for IERC20;
    using Address for address;

    uint256 public vaultId;
    uint256 public minimumInvestmentAmount;
    address public vaultCreator;
    address public factory;
    address[] public privateWalletAddresses;
    uint256 public timeLockDate;
    uint256 private totalWeightage;
    uint256 public tvl;
    struct UserInvestment {
        uint256 individualWeightage;
        uint256 amount;
    }
    mapping(address => UserInvestment) private addressToUserInvestment;

    event Invest(address investor, uint256 amount);
    event Withdraw(address withdrawer, uint256 share, uint256 amount);
    event AdminWithdraw(IERC20 token, address to, uint256 amount);
    event TokensApproved(IERC20[] tokens, uint256[] amount, address spender);
    event FeeDistribution(uint vaultCreatorReward, uint treasuryFee);
    event WithdrawTrade(address receiver, uint256 amount, uint256 amountsOut);
    event UpdatedPrivateWalletAddresses(
        address[] updatedPrivateWalletAddresses
    );
    event UpdatedMinimumInvestmentAmount(
        uint256 updatedMinimumInvestmentAmount
    );
    event ReceivedEther(address payer, uint amount);
    event FallbackReceivedEther(address payer, uint amount, bytes data);

    modifier investorCheck() {
        if (privateWalletAddresses.length > 0) {
            bool isPremium = false;
            for (uint256 i = 0; i < privateWalletAddresses.length; i++) {
                if (privateWalletAddresses[i] == msg.sender) {
                    isPremium = true;
                    break;
                }
            }
            require(isPremium, "Only premium wallet addresses allowed");
        }
        _;
    }

    modifier amountCheck(uint256 amount) {
        require(
            amount >= minimumInvestmentAmount,
            "Amount less than minimumInvestmentAmount"
        );
        _;
    }

    modifier isAdmin() {
        address treasuryContractAddress = FactoryContract(factory)
            .treasuryContractAddress();
        require(
            TreasuryContract(treasuryContractAddress).isAdmin(msg.sender),
            "Not authorized"
        );
        _;
    }

    modifier isPlatformWallet() {
        address treasuryContractAddress = FactoryContract(factory)
            .treasuryContractAddress();
        require(
            TreasuryContract(treasuryContractAddress).isPlatformWallet(
                msg.sender
            ),
            "Not authorized"
        );
        _;
    }

    modifier isTimeLockReached() {
        require(
            block.timestamp < timeLockDate,
            "Vault: exceeded timelock date"
        );
        _;
    }

    function initialize(
        uint256 _vaultId,
        address[] memory _privateWalletAddresses,
        address _vaultCreator,
        uint256 _minimumInvestmentAmount,
        address _factory
    ) external {
        vaultId = _vaultId;
        privateWalletAddresses = _privateWalletAddresses;
        vaultCreator = _vaultCreator;
        minimumInvestmentAmount = _minimumInvestmentAmount;
        factory = _factory;
        uint256 fiveYears = 365 days * 5;
        timeLockDate = block.timestamp + fiveYears;
    }

    /**
     * Receive function for receiving Ether
     */
    receive() external payable {
        emit ReceivedEther(msg.sender, msg.value);
    }

    /**
     * Fallback function for receiving Ether in case of msg.data not empty
     */
    fallback() external payable {
        emit FallbackReceivedEther(msg.sender, msg.value, msg.data);
    }

    /**
     * Allows admin to unpause the transaction related functionalities on contract
     */
    function pause() public isAdmin {
        _pause();
    }

    /**
     * Allows admin to pause the transaction related functionalities on contract
     */
    function unpause() public isAdmin {
        _unpause();
    }

    /**
     * Allows vault creator to update private wallet addresses
     */
    function updatePrivateWalletAddresses(
        address[] memory _privateWalletAddresses
    ) external isPlatformWallet whenNotPaused {
        privateWalletAddresses = _privateWalletAddresses;
        emit UpdatedPrivateWalletAddresses(privateWalletAddresses);
    }

    /**
     * Allows vault creator to update minimum investment amount
     */
    function updateMinimumInvestmentAmount(
        uint256 _minimumInvestmentAmount
    ) external isPlatformWallet whenNotPaused {
        minimumInvestmentAmount = _minimumInvestmentAmount;
        emit UpdatedMinimumInvestmentAmount(minimumInvestmentAmount);
    }

    /**
     * Function to allow users to invest in vault,
     * @param _amount amount of accepted token users wants to invest
     */
    function invest(
        uint256 _amount
    )
        external
        isTimeLockReached
        investorCheck
        amountCheck(_amount)
        whenNotPaused
    {
        address acceptedToken = FactoryContract(factory).acceptedToken();
        IERC20(acceptedToken).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        uint256 weightage = (timeLockDate - block.timestamp) * _amount;
        UserInvestment storage userInvestment = addressToUserInvestment[
            msg.sender
        ];

        userInvestment.individualWeightage =
            userInvestment.individualWeightage +
            weightage;
        userInvestment.amount = userInvestment.amount + _amount;
        totalWeightage += weightage;
        tvl += _amount;
        emit Invest(msg.sender, _amount);
    }

    /**
     * Function to send token swap function call to odos router
     * @param router address of odos router contract
     * @param data data for the function call to odos router contract
     */
    function purchase(
        address router,
        bytes memory data
    ) external isPlatformWallet whenNotPaused {
        _callMandatoryTradeData(router, data, 0);
    }

    /**
     * Sends token swap function call to odos router,
     * distributes feeAmount to the Vault creator if applicable, and the rest to the Treasury.
     * @param router address of odos router contract
     * @param data data for the function call to odos router contract
     * @param feeAmount corresponding to this trade
     */
    function copyTrade(
        address router,
        bytes memory data,
        uint feeAmount,
        uint value
    ) external isPlatformWallet whenNotPaused {
        _callMandatoryTradeData(router, data, value);
        _calculateAndSendFees(feeAmount);
    }

    /**
     * Function called by user to update share state and emit withdraw event with the calculated share
     */
    function withdraw() external whenNotPaused {
        UserInvestment memory userInvestment = addressToUserInvestment[
            msg.sender
        ];

        require(
            userInvestment.individualWeightage > 0,
            "Zero share in the vault"
        );
        uint256 share = _evaluateShares(userInvestment.individualWeightage);
        totalWeightage -= userInvestment.individualWeightage;
        tvl -= userInvestment.amount;
        delete addressToUserInvestment[msg.sender];
        emit Withdraw(msg.sender, share, userInvestment.amount);
    }

    /**
     * Sends token swap function call to odos router, sends tokens to given user's address after deducting the fees
     * and from the collected fees, distributes a share to the Vault creator if applicable, and the rest to the Treasury.
     * @param router The Address of odos router contract
     * @param data The Data for the function call to odos router contract
     */
    function withdrawal(
        address router,
        bytes memory data,
        address userWalletAddress,
        uint value,
        bool isSwapTypeSingle
    ) external isPlatformWallet whenNotPaused {
        bytes memory returndata;
        uint256 amountsOut;
        if (value == 0) {
            returndata = router.functionCall(
                data,
                "Vault: low-level call failed"
            );
        } else {
            returndata = router.functionCallWithValue(
                data,
                value,
                "Vault: low-level call with value failed"
            );
        }
        if (isSwapTypeSingle) {
            (amountsOut) = abi.decode(returndata, (uint256));
        } else {
            uint256[] memory multipleAmountsOut = abi.decode(
                returndata,
                (uint256[])
            );
            amountsOut = multipleAmountsOut[0];
        }
        uint256 txnFee = _calculateTotalFee(
            amountsOut,
            FactoryContract(factory).withdrawalFee()
        );
        uint userShare = amountsOut - txnFee;
        address acceptedToken = FactoryContract(factory).acceptedToken();
        IERC20(acceptedToken).safeTransfer(userWalletAddress, userShare);
        _calculateAndSendFees(txnFee);
        emit WithdrawTrade(userWalletAddress, userShare, amountsOut);
    }

    /**
     * Provides Approval to spender corresponding to the token addresses and their amount
     * @param _spender address of router
     * @param _tokens array of token addresses
     * @param _amount array of amount corresponding to token addresses
     */
    function approveTokens(
        address _spender,
        IERC20[] memory _tokens,
        uint256[] memory _amount
    ) external isPlatformWallet whenNotPaused {
        require(
            _tokens.length == _amount.length,
            "Vault: tokens & amount should have same length"
        );
        for (uint8 i = 0; i < _tokens.length; i++) {
            IERC20(_tokens[i]).safeIncreaseAllowance(_spender, _amount[i]);
        }
        emit TokensApproved(_tokens, _amount, _spender);
    }

    /**
     * get function to calculate given users wallet's shares for the withdrawal
     * @param _investor address of investor to calculate weightage
     */
    function evaluateShares(address _investor) external view returns (uint256) {
        UserInvestment memory userInvestment = addressToUserInvestment[
            _investor
        ];
        return _evaluateShares(userInvestment.individualWeightage);
    }

    /**
     * Allows the ADMIN_ROLE to withdraw a specified amount of ERC20 tokens or native token from the contract.
     * @param _tokenAddress The address of ERC20 token to withdraw
     * @param _to The address to send the tokens to
     * @param _amount amount of tokens to withdraw, if equals 0, it transfers the available balance of the token.
     */
    function adminWithdrawFunds(
        IERC20 _tokenAddress,
        address _to,
        uint256 _amount
    ) external isAdmin {
        require(_to != address(0), "address zero not allowed");
        uint256 amount;
        if (address(_tokenAddress) == address(0)) {
            uint256 balance = address(this).balance;
            require(balance > 0, "Insufficient native balance");
            amount = _amount == 0 ? balance : _amount;
            bool sent = _sendEthersTo(_to, amount);
            require(sent, "Failed to send native token");
        } else {
            uint256 balance = IERC20(_tokenAddress).balanceOf(address(this));
            require(balance > 0, "Insufficient balance");
            amount = _amount == 0 ? balance : _amount;
            _tokenAddress.safeTransfer(_to, amount);
        }
        emit AdminWithdraw(_tokenAddress, _to, amount);
    }

    /**
     * Function to Send ETH
     * @param _receiver address of receipient
     * @param _amount amount of ETH to transfer
     * @return bool
     */
    function _sendEthersTo(
        address _receiver,
        uint256 _amount
    ) private returns (bool) {
        (bool sent, ) = payable(_receiver).call{value: _amount}("");
        return sent;
    }

    /**
     * get function to calculate given users wallet's shares for the withdrawal
     * @param weightage user's individual weightage
     */
    function _evaluateShares(uint weightage) private view returns (uint256) {
        return
            totalWeightage > 0
                ? (weightage * TOTAL_BASIS_POINT) / totalWeightage
                : 0;
    }

    /**
     * Calculate and distribute fee share to the Treausry contract and vault creator (if applied).
     * @param _txnFeeAmount fee amount for the transaction
     */
    function _calculateAndSendFees(uint256 _txnFeeAmount) private {
        (
            uint256 feeToTreasury,
            uint256 rewardToVaultCreator
        ) = _calculateFeeDistribution(
                _txnFeeAmount,
                FactoryContract(factory).getVaultCreatorReward(
                    vaultCreator,
                    tvl
                )
            );

        address treasuryContractAddress = FactoryContract(factory)
            .treasuryContractAddress();
        address acceptedToken = FactoryContract(factory).acceptedToken();

        IERC20(acceptedToken).safeTransfer(
            treasuryContractAddress,
            feeToTreasury
        );
        if (rewardToVaultCreator > 0) {
            IERC20(acceptedToken).safeTransfer(
                vaultCreator,
                rewardToVaultCreator
            );
        }

        emit FeeDistribution(rewardToVaultCreator, feeToTreasury);
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is mandatory (returndata.length > 0).
     * @param targetContract The contract address targeted by the call.
     * @param data The call data .
     * @param value of Native token
     */
    function _callMandatoryTradeData(
        address targetContract,
        bytes memory data,
        uint value
    ) private {
        if (value == 0) {
            targetContract.functionCall(data, "Vault: low-level call failed");
        } else {
            targetContract.functionCallWithValue(
                data,
                value,
                "Vault: low-level call with value failed"
            );
        }
    }
}

