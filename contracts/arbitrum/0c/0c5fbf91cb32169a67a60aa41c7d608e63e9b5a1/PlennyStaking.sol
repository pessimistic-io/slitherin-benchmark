// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./SafeMathUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./PlennyBasePausableV2.sol";
import "./IPlennyERC20.sol";
import "./PlennyStakingStorage.sol";
import "./PlennyLiqMiningStorage.sol";
import "./IPlennyStaking.sol";

/// @title  PlennyStaking
/// @notice Manages staking of PL2 for the capacity market, delegation and for oracle validators.
contract PlennyStaking is PlennyBasePausableV2, PlennyStakingStorage {

    using SafeMathUpgradeable for uint256;
    using AddressUpgradeable for address payable;
    using SafeERC20Upgradeable for IPlennyERC20;

    /// An event emitted when logging function calls.
    event LogCall(bytes4  indexed sig, address indexed caller, bytes data) anonymous;

    /// @notice Initializes the smart contract instead of a constructor. Called once during deploy.
    /// @param  _registry Plenny contract registry
    function initialize(address _registry) external initializer {
        // 1 %
        withdrawFee = 100;

        PlennyBasePausableV2.__plennyBasePausableInit(_registry);
    }

    /// @notice Stakes PL2 for the purpose of the Lightning marketplace, delegation and validation.
    /// @param  amount amount to stake
    function stakePlenny(uint256 amount) external whenNotPaused nonReentrant {
        _logs_();
        _setPlennyBalanceInternal(msg.sender, plennyBalance[msg.sender] + amount);
        contractRegistry.factoryContract().increaseDelegatedBalance(msg.sender, amount);
        contractRegistry.plennyTokenContract().safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @notice Unstakes PL2 from marketplace. If the user is an oracle, a minimum oracle amount needs to be kept staked.
    ///         A fee is charged on unstaking.
    /// @param  amount amount to unstake
    /// @return uint256 amount that was unstacked.
    function unstakePlenny(uint256 amount) external whenNotPaused nonReentrant returns (uint256) {
        _logs_();
        require(plennyBalance[msg.sender] >= amount, "ERR_NO_FUNDS");

        IPlennyDappFactory factory = contractRegistry.factoryContract();
        // check if the user is oracle
        if (factory.isOracleValidator(msg.sender)) {
            uint256 defaultLockingAmount = factory.defaultLockingAmount();
            require(plennyBalance[msg.sender] >= defaultLockingAmount, "ERR_NO_FUNDS");
            require(plennyBalance[msg.sender] - defaultLockingAmount >= amount, "ERR_NO_FUNDS");
        }

        _setPlennyBalanceInternal(msg.sender, plennyBalance[msg.sender] - amount);
        factory.decreaseDelegatedBalance(msg.sender, amount);

        uint256 fee = amount.mul(withdrawFee).div(100);

        uint256 actualAmount = amount - fee.div(100);

        IPlennyERC20 token = contractRegistry.plennyTokenContract();
        token.safeTransfer(contractRegistry.requireAndGetAddress("PlennyRePLENishment"), fee.div(100));
        token.safeTransfer(msg.sender, actualAmount);
        return actualAmount;
    }

    /// @notice Whenever a Plenny staking balance is increased.
    /// @param  userAddress address of the user
    /// @param  amount increasing amount
    function increasePlennyBalance(address userAddress, uint256 amount, address from) external override {
        _onlyAuth();
        _logs_();

        _setPlennyBalanceInternal(userAddress, plennyBalance[userAddress] += amount);
        contractRegistry.factoryContract().increaseDelegatedBalance(userAddress, amount);
        contractRegistry.plennyTokenContract().safeTransferFrom(from, address(this), amount);
    }

    /// @notice Whenever a Plenny staking balance is decreased.
    /// @param  userAddress address of the user
    /// @param  amount decreased amount
    /// @param  to sending to
    function decreasePlennyBalance(address userAddress, uint256 amount, address to) external override {
        _onlyAuth();
        _logs_();

        require(plennyBalance[userAddress] >= amount, "ERR_NO_FUNDS");
        _setPlennyBalanceInternal(userAddress, plennyBalance[userAddress] -= amount);
        contractRegistry.factoryContract().decreaseDelegatedBalance(userAddress, amount);
        contractRegistry.plennyTokenContract().safeTransfer(to, amount);
    }

    /// @notice Changes the fee for withdrawing. Called by the owner.
    /// @param  newWithdrawFee new withdrawal fee in percentage
    function setWithdrawFee(uint256 newWithdrawFee) external onlyOwner {
        require(newWithdrawFee < 10001, "ERR_WRONG_STATE");
        withdrawFee = newWithdrawFee;
    }

    /// @notice Number of plenny stakers.
    /// @return uint256 count
    function plennyOwnersCount() external view returns (uint256) {
        return plennyOwners.length;
    }

    /// @notice Manage the plenny staking balance.
    /// @param  dapp address
    /// @param  amount setting amount
    function _setPlennyBalanceInternal(address dapp, uint256 amount) internal {
        plennyBalance[dapp] = amount;
        _pushPlennyOwnerInternal(dapp);
    }

    /// @notice Manage the plenny stakers count.
    /// @param  plennyOwner add staker
    function _pushPlennyOwnerInternal(address plennyOwner) internal {
        if (!plennyOwnerExists[plennyOwner]) {
            plennyOwners.push(plennyOwner);
            plennyOwnerExists[plennyOwner] = true;
        }
    }

    /// @dev    logs the function calls.
    function _logs_() internal {
        emit LogCall(msg.sig, msg.sender, msg.data);
    }

    /// @dev    Only the authorized contracts can make requests.
    function _onlyAuth() internal view {
        require(contractRegistry.getAddress("PlennyLiqMining") == msg.sender || contractRegistry.requireAndGetAddress("PlennyOracleValidator") == msg.sender ||
        contractRegistry.requireAndGetAddress("PlennyCoordinator") == msg.sender || contractRegistry.requireAndGetAddress("PlennyOcean") == msg.sender, "ERR_NOT_AUTH");
    }
}

