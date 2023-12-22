// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./SafeMath.sol";
import "./IsArbet.sol";
import "./Reflection.sol";

contract Vault is Reflection {
    using SafeMath for uint256;

    struct WithdrawContext {
        uint256 nextWithdrawTime;
        uint256 steps;
    }

    error CannotWithdraw(address _staker, uint256 total, uint256 amount);

    IERC20 public vaultToken;
    IsArbet public sArbetToken;

    uint256 constant private RESOLUTION = 10000;
    uint256 public depositFee = 100;  // 1%
    uint256 public withdrawDuration = 1 days;

    mapping (address => bool) isGameContracts;
    mapping (address => WithdrawContext) wthctx;

    address public treasuryWallet;
    uint256 public feeToVault;
    uint256 public feeToSArbet;

    bool isEntering;

    modifier nonReentrant() {
        require(!isEntering, "Already Entering");
        isEntering = true;
        _;
        isEntering = false;
    }

    modifier onlyGameContracts() {
        require(isGameContracts[msg.sender], "Not Game Contract");
        _;
    }

    constructor (address _vaultToken, address _sArbet, string memory _vaultName, string memory _vaultSymbol) Reflection(_vaultName, _vaultSymbol) {
        vaultToken = IERC20(_vaultToken);
        sArbetToken = IsArbet(_sArbet);
        treasuryWallet = 0x1ac8436caF7e72E730a30Cdb04D4400580b9Eaae;
        feeToVault = 3000; // 30%
        feeToSArbet = 6000; // 60%
    }

    function depositVault(uint256 _amount) external payable nonReentrant {
        address snder = msg.sender;

        if (address(vaultToken) == address(0)) {
            _amount = msg.value;
            require(_amount > 0, "No ETH to deposit");
        } else {
            uint256 oldb = vaultToken.balanceOf(address(this));
            vaultToken.transferFrom(snder, address(this), _amount);
            uint256 newb = vaultToken.balanceOf(address(this));

            require(newb > oldb, "Zero to deposit");
            _amount = newb - oldb;
        }

        uint256 _fee = _amount.mul(depositFee).div(RESOLUTION);
        _amount = _amount.sub(_fee);

        deposit(snder, _amount);

        distributeFees(_fee);

        WithdrawContext storage wc = wthctx[snder];
        wc.nextWithdrawTime = block.timestamp + withdrawDuration;
        wc.steps = 4;
    }

    function withdrawVault() external payable nonReentrant {
        address snder = msg.sender;

        uint256 amount = getDepositedAmount(snder);
        if (amount == 0) return;

        WithdrawContext storage wc = wthctx[snder];
        require(wc.nextWithdrawTime <= block.timestamp, "Locked Withdraw");
        require(wc.steps > 0, "Fully Withdrawn");

        wc.nextWithdrawTime = block.timestamp + withdrawDuration;
        amount = amount.div(wc.steps);
        wc.steps = wc.steps.sub(1);

        uint256 pending = getPendingReward(snder);

        uint256 total;
        if (address(vaultToken) == address(0)) {
            total = address(this).balance;
        } else {
            total = vaultToken.balanceOf(address(this));
        }

        if (total < amount.add(pending)) {
            revert CannotWithdraw(snder, total, amount.add(pending));
        }

        if (address(vaultToken) == address(0)) {
            payable(snder).transfer(amount);
        } else {
            vaultToken.transfer(snder, amount);
        }

        withdraw(snder, amount);
    }

    function claimVault() external payable nonReentrant {
        uint256 amount = _claimProvision(msg.sender);
        if (amount == 0) {
            revert ClaimNull(msg.sender);
        }
    }

    function _claimProvision(address user) internal virtual override returns (uint256) {
        uint256 amount = super._claimProvision(user);
        if (amount > 0) {
            if (address(vaultToken) == address(0)) {
                payable(user).transfer(amount);
            } else {
                vaultToken.transfer(user, amount);
            }
        }
        return amount;
    }

    function withdrawToTreasury(uint256 _amount) external payable nonReentrant onlyOwner {
        uint256 _balance = vaultToken.balanceOf(address(this));
        uint256 vaultThreshold = totalSupply().mul(13000).div(RESOLUTION); // over 130% of total deposited usdt

        if(_balance >= _amount + vaultThreshold) {
            if (address(vaultToken) == address(0)) {
                payable(msg.sender).transfer(_amount);
            } else {
                vaultToken.transfer(msg.sender, _amount);
            }
        }
    }

    function distributeFees(uint256 _fee) private {
        uint256 _rewardForVault = _fee.mul(feeToVault).div(RESOLUTION);
        uint256 _rewardForArbet = _fee.mul(feeToSArbet).div(RESOLUTION);
        uint256 _rewardForTreasury = _fee.sub(_rewardForVault).sub(_rewardForArbet);

        provide(_rewardForVault);

        if (address(vaultToken) == address(0)) {
            sArbetToken.addReward{value: _rewardForArbet}(_rewardForArbet);
            payable(treasuryWallet).transfer(_rewardForTreasury);
        } else {
            vaultToken.approve(address(sArbetToken), _rewardForArbet);
            sArbetToken.addReward(_rewardForArbet);
            vaultToken.transfer(treasuryWallet, _rewardForTreasury);
        }
    }

    function finalizeGame(address _player, uint256 _prize, uint256 _fee) external payable nonReentrant onlyGameContracts {
        if (_prize > 0) {
            if (address(vaultToken) == address(0)) {
                payable(_player).transfer(_prize);
            } else {
                vaultToken.transfer(_player, _prize);
            }
        }

        if (_fee > 0) {
            distributeFees(_fee);
        }
    }

    function setTreasuryWallet(address newTreasury) external onlyOwner {
        require(treasuryWallet != newTreasury, "Already Set");
        treasuryWallet = newTreasury;
    }

    function setDistributeFee(uint256 vault, uint256 arbet) external onlyOwner {
        require(vault + arbet <= RESOLUTION, "Over 100%");
        feeToVault = vault;
        feeToSArbet = arbet;
    }

    function setDepositFee(uint256 _fee) external onlyOwner {
        depositFee = _fee;
    }

    function setWithdrawDuration(uint256 newDuration) external onlyOwner {
        require(withdrawDuration != newDuration, "Already Set");
        withdrawDuration = newDuration;
    }

    function setsArbetToken(address _sArbet) external onlyOwner {
        sArbetToken = IsArbet(_sArbet);
    }

    function setDepositToken(address _newDepositToken) external onlyOwner {
        vaultToken = IERC20(_newDepositToken);
    }

    function addToGameContractList(address _game) external onlyOwner {
        isGameContracts[_game] = true;
    }

    function removeFromGameContractList(address _game) external onlyOwner {
        isGameContracts[_game] = false;
    }

    function getWithdrawInfo(address _user) external view returns (WithdrawContext memory) {
        return wthctx[_user];
    }

    receive() external payable {
    }
}

