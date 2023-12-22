//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { AccessControl } from "./AccessControl.sol";
import { BalanceUpdate, UserBalanceUpdate, ProtocolBalanceUpdate } from "./Structs.sol";
import { IERC20 } from "./IERC20.sol";
import { IPepeBetPool } from "./IPepeBetPool.sol";
import { SafeERC20 } from "./SafeERC20.sol";

contract PepeBetPool is IPepeBetPool, AccessControl {
    using SafeERC20 for IERC20;
    bytes32 public constant PEPE_ADMIN_ROLE = keccak256("PEPE_ADMIN_ROLE");
    bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR_ROLE");
    bytes32 public constant WITHDRAWER_ROLE = keccak256("WITHDRAWER_ROLE");

    address public feeDistributor;
    address public serviceWallet;

    mapping(address user => mapping(address token => uint256 balance)) public balances;
    mapping(address token => uint256 balance) public pepePoolBalanceByToken;
    mapping(address token => uint256 balance) public pepeFeeTakerBalanceByToken;
    mapping(address token => bool isApproved) public approvedTokens;

    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Withdrawal(address indexed user, address indexed token, uint256 amount);
    event UserBalanceUpdated(address indexed user, address indexed token, uint256 prevBalance, uint256 newBalance);
    event FeesUpdated(address indexed token, uint256 accumulatedFees);
    event ApprovedTokens(address indexed token);
    event RevokedTokens(address indexed token);
    event DepositedToPepePool(address indexed token, uint256 prevBalance, uint256 newBalance);
    event PepePoolBalanceUpdated(address indexed token, uint256 prevBalance, uint256 newBalance);
    event PepePoolBalanceWithdrawn(address indexed to, address indexed token, uint256 amount);
    event FeesTransferred(address indexed to, address indexed token, uint256 amount);
    event FundedServiceWallet(address indexed to, address indexed token, uint256 amount);
    event FeesWithdrawn(address indexed to, address indexed token, uint256 amount);
    event ServiceWalletChanged(address indexed newServiceWallet);
    event FeeDistributorChanged(address indexed newFeeDistributor);
    event Retrieved(address indexed token, uint256 amount);

    modifier onlyApprovedRole() {
        require(
            hasRole(PEPE_ADMIN_ROLE, msg.sender) ||
                hasRole(DEPOSITOR_ROLE, msg.sender) ||
                hasRole(WITHDRAWER_ROLE, msg.sender),
            "!approved"
        );
        _;
    }

    constructor(address feeDistributor_, address serviceWallet_) {
        feeDistributor = feeDistributor_;
        serviceWallet = serviceWallet_;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PEPE_ADMIN_ROLE, msg.sender);
        _grantRole(DEPOSITOR_ROLE, msg.sender);
        _grantRole(WITHDRAWER_ROLE, msg.sender);
    }

    function deposit(
        address user,
        address token,
        uint256 amount,
        BalanceUpdate calldata balanceUpdate
    ) external override onlyRole(DEPOSITOR_ROLE) {
        require(amount != 0, "!amount");
        require(approvedTokens[token], "!approved");

        ///@dev update the balance of only @param user
        require(balanceUpdate.userBalanceUpdate.length == 1, "!userBalanceUpdate");

        syncBalances(balanceUpdate);

        IERC20(token).safeTransferFrom(user, address(this), amount);
        balances[user][token] += amount;

        emit Deposit(user, token, amount);
    }

    function withdraw(
        address user,
        address token,
        uint256 amount,
        BalanceUpdate calldata balanceUpdate
    ) external override onlyRole(WITHDRAWER_ROLE) {
        require(amount != 0, "!amount");
        ///@dev update the balance of only the balance of @param user
        require(balanceUpdate.userBalanceUpdate.length == 1, "!userBalanceUpdate");

        syncBalances(balanceUpdate);
        require(balances[user][token] >= amount, "!balance");

        balances[user][token] -= amount;
        IERC20(token).safeTransfer(user, amount);

        emit Withdrawal(user, token, amount);
    }

    function depositToPool(
        address token,
        uint256 amount,
        BalanceUpdate calldata balanceUpdate
    ) external override onlyRole(PEPE_ADMIN_ROLE) {
        require(approvedTokens[token], "!approved");
        syncBalances(balanceUpdate);

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        pepePoolBalanceByToken[token] += amount;

        emit DepositedToPepePool(token, pepePoolBalanceByToken[token] - amount, pepePoolBalanceByToken[token]);
    }

    function withdrawFromPool(
        address token,
        uint256 amount,
        BalanceUpdate calldata balanceUpdate
    ) external override onlyRole(PEPE_ADMIN_ROLE) {
        syncBalances(balanceUpdate);
        require(amount <= pepePoolBalanceByToken[token], "insufficient pool balance");
        pepePoolBalanceByToken[token] -= amount;
        IERC20(token).safeTransfer(msg.sender, amount);

        emit PepePoolBalanceWithdrawn(msg.sender, token, amount);
    }

    function transferFeesToDistributor(
        address token,
        uint256 amount,
        BalanceUpdate calldata balanceUpdate
    ) external override onlyRole(PEPE_ADMIN_ROLE) {
        syncBalances(balanceUpdate);
        require(amount <= pepeFeeTakerBalanceByToken[token], "insufficient fee balance");
        pepeFeeTakerBalanceByToken[token] -= amount;
        IERC20(token).safeTransfer(feeDistributor, amount);

        emit FeesTransferred(feeDistributor, token, amount);
    }

    function withdrawFees(
        address token,
        uint256 amount,
        BalanceUpdate calldata balanceUpdate
    ) external override onlyRole(PEPE_ADMIN_ROLE) {
        syncBalances(balanceUpdate);
        require(amount <= pepeFeeTakerBalanceByToken[token], "insufficient fee balance");
        pepeFeeTakerBalanceByToken[token] -= amount;
        IERC20(token).safeTransfer(msg.sender, amount);

        emit FeesWithdrawn(msg.sender, token, amount);
    }

    function fundServiceWallet(address token, uint256 amount, BalanceUpdate calldata balanceUpdate) external override {
        syncBalances(balanceUpdate);
        require(msg.sender == serviceWallet || hasRole(PEPE_ADMIN_ROLE, msg.sender), "!serviceWallet or !admin");
        require(amount <= pepePoolBalanceByToken[token], "insufficient pool balance");

        pepePoolBalanceByToken[token] -= amount;
        IERC20(token).safeTransfer(serviceWallet, amount);

        emit FundedServiceWallet(serviceWallet, token, amount);
    }

    function syncBalances(BalanceUpdate calldata balanceUpdate) public override onlyApprovedRole {
        UserBalanceUpdate[] memory userBalanceUpdate = balanceUpdate.userBalanceUpdate;
        ProtocolBalanceUpdate[] memory protocolBalUpdate = balanceUpdate.protocolBalanceUpdate;

        uint256 balanceUpdateLength = userBalanceUpdate.length;
        uint256 protocolUpdateLength = protocolBalUpdate.length;
        uint256 i;
        uint256 j;

        for (; i < balanceUpdateLength; ) {
            UserBalanceUpdate memory update = balanceUpdate.userBalanceUpdate[i];

            uint256 prevBalance = balances[update.user][update.token];

            if (prevBalance != update.newBalance) {
                balances[update.user][update.token] = update.newBalance;
                emit UserBalanceUpdated(update.user, update.token, prevBalance, update.newBalance);
            }

            unchecked {
                ++i;
            }
        }

        for (; j < protocolUpdateLength; ) {
            ProtocolBalanceUpdate memory update = balanceUpdate.protocolBalanceUpdate[j];

            uint256 prevFeeBalance = pepeFeeTakerBalanceByToken[update.token];
            if (update.accumulatedFees != prevFeeBalance) {
                pepeFeeTakerBalanceByToken[update.token] += update.accumulatedFees;

                emit FeesUpdated(update.token, update.accumulatedFees);
            }

            uint256 prevPoolBalance = pepePoolBalanceByToken[update.token];
            if (update.newPoolBalance != prevPoolBalance) {
                pepePoolBalanceByToken[update.token] = update.newPoolBalance;

                emit PepePoolBalanceUpdated(update.token, prevPoolBalance, update.newPoolBalance);
            }

            unchecked {
                ++j;
            }
        }
    }

    function approveTokens(address[] calldata tokens) external override onlyRole(PEPE_ADMIN_ROLE) {
        uint256 tokensLength = tokens.length;
        uint256 i;
        for (; i < tokensLength; ) {
            address token = tokens[i];
            require(!approvedTokens[token], "already approved");
            require(token != address(0), "token is zero address");

            approvedTokens[token] = true;

            emit ApprovedTokens(token);

            unchecked {
                ++i;
            }
        }
    }

    function revokeTokens(address[] calldata tokens) external override onlyRole(PEPE_ADMIN_ROLE) {
        uint256 tokensLength = tokens.length;
        uint256 i;
        for (; i < tokensLength; ) {
            address token = tokens[i];
            require(approvedTokens[token], "not approved");
            require(token != address(0), "token is zero address");

            approvedTokens[token] = false;

            emit RevokedTokens(token);

            unchecked {
                ++i;
            }
        }
    }

    function changeServiceWallet(address newServiceWallet) external override onlyRole(PEPE_ADMIN_ROLE) {
        require(newServiceWallet != address(0), "zero address");
        serviceWallet = newServiceWallet;

        emit ServiceWalletChanged(newServiceWallet);
    }

    function changeFeeDistributor(address newFeeDistributor) external override onlyRole(PEPE_ADMIN_ROLE) {
        require(newFeeDistributor != address(0), "zero address");
        feeDistributor = newFeeDistributor;

        emit FeeDistributorChanged(newFeeDistributor);
    }

    function retrieve(address token) external override onlyRole(PEPE_ADMIN_ROLE) {
        require(!approvedTokens[token], "approved token");
        uint256 ethBalance = address(this).balance;
        if (ethBalance != 0) {
            (bool success, ) = payable(msg.sender).call{ value: ethBalance }("");
            require(success, "ETH retrival failed");
        }

        uint256 amount = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(msg.sender, amount);

        emit Retrieved(token, amount);
    }
}

