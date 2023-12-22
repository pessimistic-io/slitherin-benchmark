// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.21;

import "./SafeERC20.sol";
import "./Pausable.sol";
import "./Address.sol";
import {FactoryContract} from "./IFactory.sol";
import {TreasuryContract} from "./ITreasury.sol";
import {VaultFeeHandler} from "./VaultFeeHandler.sol";
import "./Initializable.sol";

contract Vault is Context, Initializable, Pausable, VaultFeeHandler {
    using SafeERC20 for IERC20;
    using Address for address;

    string public vaultId;
    uint256 public minimumInvestmentAmount;
    address public vaultCreator;
    address public factory;
    address[] public whitelistAddresses;
    uint256 public tvl;
    enum TradeType {
        CopyTrade,
        Withdrawal
    }
    mapping(address => uint256) public addressToUserInvestment;

    event Invest(address investor, uint256 amount);
    event Withdraw(address withdrawer, uint256 amount);
    event EmergencyWithdrawn(IERC20 token, address to, uint256 amount);
    event TokensApproved(IERC20[] tokens, uint256[] amount, address spender);
    event FeeDistribution(
        TradeType,
        uint256 vaultCreatorReward,
        uint256 treasuryFee
    );
    event WithdrawTrade(
        address receiver,
        uint256 userShare,
        uint256 totalAmount
    );
    event UpdatedWhitelistedWalletAddresses(
        address[] updatedWhitelistedWalletAddresses
    );
    event UpdatedMinimumInvestmentAmount(
        uint256 updatedMinimumInvestmentAmount
    );
    event ReceivedEther(address payer, uint256 amount);
    event FallbackReceivedEther(address payer, uint256 amount, bytes data);

    modifier investorCheck() {
        if (whitelistAddresses.length > 0) {
            bool isWhitelisted = false;
            for (uint256 i = 0; i < whitelistAddresses.length; i++) {
                if (whitelistAddresses[i] == msg.sender) {
                    isWhitelisted = true;
                    break;
                }
            }
            require(isWhitelisted, "Only whitelisted wallet addresses allowed");
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

    /**
     * @notice Function to initialize a vault contract and set value of variable as provided in below parameter.
     * @param _vaultId Unique vault id in string format.
     * @param _whitelistAddresses List of wallet address that are allowed to invest in vault.
     * @param _vaultCreator Wallet address of user requested for vault deployment.
     * @param _minimumInvestmentAmount Minimum amount of investment allowed to invest in vault.
     * @param _factory Address of factory contract.
     */

    function initialize(
        string memory _vaultId,
        address[] memory _whitelistAddresses,
        address _vaultCreator,
        uint256 _minimumInvestmentAmount,
        address _factory
    ) external initializer {
        vaultId = _vaultId;
        whitelistAddresses = _whitelistAddresses;
        vaultCreator = _vaultCreator;
        minimumInvestmentAmount = _minimumInvestmentAmount;
        factory = _factory;
    }

    /**
     * @notice Receive function for receiving Ether.
     */
    receive() external payable {
        emit ReceivedEther(msg.sender, msg.value);
    }

    /**
     * @notice Fallback function for receiving Ether in case of msg.data not empty.
     */
    fallback() external payable {
        emit FallbackReceivedEther(msg.sender, msg.value, msg.data);
    }

    /**
     * @notice Function to allow ADMIN_ROLE to pause the transactions which result in transactions failing which have whenNotPaused modifier attached.
     */
    function pause() public isAdmin {
        _pause();
    }

    /**
     * @notice Function to allow ADMIN_ROLE to unpause the transaction which result in successfull transactions which have whenNotPaused modifier attached.
     */
    function unpause() public isAdmin {
        _unpause();
    }

    /**
     * @notice Function to allow the ADMIN_ROLE to withdraw a specified amount of ERC20 tokens or native token from the contract,in case of any malicious activity.
     * @param _tokenAddress The address of ERC20 token to withdraw
     * @param _to The address to send the tokens to
     * @param _amount Amount of tokens to withdraw, if equals 0, it transfers the available balance of the token.
     */
    function emergencyWithdrawFunds(
        IERC20 _tokenAddress,
        address _to,
        uint256 _amount
    ) external isAdmin {
        require(_to != address(0), "Address zero not allowed");
        uint256 amount;
        if (address(_tokenAddress) == address(0)) {
            uint256 balance = address(this).balance;
            require(balance > 0, "Insufficient native balance");
            amount = _amount == 0 ? balance : _amount;
            bool sent = _sendEthersTo(_to, amount);
            require(sent, "Failed to send native token");
        } else {
            uint256 balance = _tokenAddress.balanceOf(address(this));
            require(balance > 0, "Insufficient balance");
            amount = _amount == 0 ? balance : _amount;
            _tokenAddress.safeTransfer(_to, amount);
        }
        emit EmergencyWithdrawn(_tokenAddress, _to, amount);
    }

    /**
     * @notice Function to allow platform wallet to update private wallet addresses,only accessible by PLATFORM_ROLE.
     * @param _whitelistAddresses Whitelisted wallet addresses that can invest in this vault.
     */
    function updateWhitelistedWalletAddresses(
        address[] memory _whitelistAddresses
    ) external isPlatformWallet whenNotPaused {
        whitelistAddresses = _whitelistAddresses;
        emit UpdatedWhitelistedWalletAddresses(whitelistAddresses);
    }

    /**
     * @notice Function to allow platform wallet to update minimum investment amount,only accessible by PLATFORM_ROLE.
     * @param _minimumInvestmentAmount Minimum investment that user needs to do in one single trade.
     */
    function updateMinimumInvestmentAmount(
        uint256 _minimumInvestmentAmount
    ) external isPlatformWallet whenNotPaused {
        minimumInvestmentAmount = _minimumInvestmentAmount;
        emit UpdatedMinimumInvestmentAmount(minimumInvestmentAmount);
    }

    /**
     * @notice Function to send token swap function call to odos router,only accessible by PLATFORM_ROLE.
     * @param router Address of odos router contract.
     * @param data Data for the function call to odos router contract.
     */
    function purchase(
        address router,
        bytes memory data
    ) external isPlatformWallet whenNotPaused {
        router.functionCallWithValue(data, 0, "Vault: low-level call failed");
    }

    /**
     * @notice Function to send token swap function call to odos router,
     * distributes feeAmount to the Vault creator if applicable, and the rest to Treasury,only accessible by PLATFORM_ROLE.
     * @param router Address of odos router contract.
     * @param data Data for the function call to odos router contract.
     * @param feeAmount Fees corresponding to this trade.
     * @param  isSwapTypeSingle Whether the swap is 1:1 or not.
     * @param value  Amount of Native token
     */
    function copyTrade(
        address router,
        bytes memory data,
        uint256 feeAmount,
        bool isSwapTypeSingle,
        uint256 value
    ) external isPlatformWallet whenNotPaused {
        uint256 amountsOut = _callMandatoryTradeDataForAcceptedToken(
            router,
            data,
            isSwapTypeSingle,
            value
        );
        feeAmount = amountsOut > feeAmount ? feeAmount : amountsOut;
        _calculateAndSendFees(TradeType.CopyTrade, feeAmount);
    }

    /**
     * @notice Sends token swap function call to odos router, sends tokens to given user's address after deducting the fees
     * and from the collected fees distributes a share to the Vault creator if applicable and the rest to the Treasury,only accessible by PLATFORM_ROLE.
     * @param router The Address of odos router contract.
     * @param data The Data for the function call to odos router contract.
     * @param userWalletAddress User for which this trade is executed.
     * @param value Amount of accepted token.
     * @param  isSwapTypeSingle Whether the swap is 1:1 or not.
     * @param value Amount of Native token.
     */
    function withdrawal(
        address router,
        bytes memory data,
        address userWalletAddress,
        uint256 acceptedTokenAmount,
        bool isSwapTypeSingle,
        uint256 value
    ) external isPlatformWallet whenNotPaused {
        uint256 amountsOut = _callMandatoryTradeDataForAcceptedToken(
            router,
            data,
            isSwapTypeSingle,
            value
        );
        uint256 totalAmount = amountsOut + acceptedTokenAmount;
        uint256 txnFee = _calculateTotalFee(
            totalAmount,
            FactoryContract(factory).withdrawalFee()
        );
        uint256 userShare = totalAmount - txnFee;
        address acceptedToken = FactoryContract(factory).acceptedToken();
        IERC20(acceptedToken).safeTransfer(userWalletAddress, userShare);
        _calculateAndSendFees(TradeType.Withdrawal, txnFee);
        emit WithdrawTrade(userWalletAddress, userShare, totalAmount);
    }

    /**
     * @notice Provides Approval to spender corresponding to the token addresses and their amount,only accessible by PLATFORM_ROLE.
     * @param _spender Address of router
     * @param _tokens Array of token addresses
     * @param _amount Array of amount corresponding to token addresses
     */
    function approveTokens(
        address _spender,
        IERC20[] memory _tokens,
        uint256[] memory _amount
    ) external isPlatformWallet whenNotPaused {
        require(
            _tokens.length == _amount.length,
            "Tokens & amount should have same length"
        );
        for (uint8 i = 0; i < _tokens.length; i++) {
            IERC20(_tokens[i]).safeIncreaseAllowance(_spender, _amount[i]);
        }
        emit TokensApproved(_tokens, _amount, _spender);
    }

    /**
     * @notice Function to allow users to invest in vault.
     * @param _amount Amount of accepted token users wants to invest.
     */
    function invest(
        uint256 _amount
    ) external investorCheck amountCheck(_amount) whenNotPaused {
        address acceptedToken = FactoryContract(factory).acceptedToken();
        IERC20(acceptedToken).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
        addressToUserInvestment[msg.sender] += _amount;
        tvl += _amount;
        emit Invest(msg.sender, _amount);
    }

    /**
     * @notice Function to withdraw investment by user which update tvl state and emit withdraw event.
     */
    function withdraw() external whenNotPaused {
        uint256 investmentAmount = addressToUserInvestment[msg.sender];
        require(investmentAmount > 0, "No investment in the vault");
        tvl -= investmentAmount;
        delete addressToUserInvestment[msg.sender];
        emit Withdraw(msg.sender, investmentAmount);
    }

    /**
     * @dev Function to calculate and distribute fee share to the Treausry contract and vault creator (if applied).
     * @param _txnFeeAmount Fee amount for the transaction.
     */
    function _calculateAndSendFees(
        TradeType tradeType,
        uint256 _txnFeeAmount
    ) internal {
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

        emit FeeDistribution(tradeType, rewardToVaultCreator, feeToTreasury);
    }

    /**
     * @dev Function to Send ETH.
     * @param _receiver Address of receipient.
     * @param _amount Amount of ETH to transfer.
     * @return Status of transaction.
     */
    function _sendEthersTo(
        address _receiver,
        uint256 _amount
    ) private returns (bool) {
        (bool sent, ) = payable(_receiver).call{value: _amount}("");
        return sent;
    }

    /**
     * @dev Function to imitate a Solidity high-level call (i.e. a regular function call to a contract) and return amountsOut for accepted token.
     * @param targetContract The contract address targeted by the call.
     * @param data The call data .
     * @param  isSwapTypeSingle Whether the swap is 1:1 or not.
     * @param value Amount of Native token.
     * @return Amount of accepted token.
     */
    function _callMandatoryTradeDataForAcceptedToken(
        address targetContract,
        bytes memory data,
        bool isSwapTypeSingle,
        uint256 value
    ) private returns (uint256) {
        uint256 amountsOut;
        bytes memory returndata = targetContract.functionCallWithValue(
            data,
            value,
            "Vault: low-level call failed"
        );
        if (isSwapTypeSingle) {
            (amountsOut) = abi.decode(returndata, (uint256));
        } else {
            uint256[] memory multipleAmountsOut = abi.decode(
                returndata,
                (uint256[])
            );
            amountsOut = multipleAmountsOut[0];
        }
        return amountsOut;
    }
}

