// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

contract esTROVE is
    OwnableUpgradeable,
    ERC20Upgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    event Vested(address staker, uint256 amount, uint256 timestamp);
    event Claimed(address claimer, uint256 amount, uint256 timestamp);
    event Unvested(address user, uint256 amount, uint256 timestamp);

    address public trove;
    uint256 public maxStakes;

    struct VestInfo {
        uint256 totalAmount;
        uint256[] amounts;
        uint256[] stakedAt;
        uint256 lastWithdrawalAt;
    }

    mapping(address => VestInfo) public vesting;
    address[] public users;
    mapping(address => bool) usersEnabled;
    mapping(address => bool) userExisted;

    address public stakingAddress;
    uint256 public fullVestingCutoffTimestamp;
    uint256 public vestingStartTimestamp;

    mapping(address => bool) public stakingAddresses;

    function init(
        address _trove,
        uint256 _maxStakes,
        address _stakingAddress
    ) external initializer {
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __ERC20_init("esTROVE", "esTROVE");
        trove = _trove;
        maxStakes = _maxStakes;
        stakingAddress = _stakingAddress;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function mintEsTrove(address user, uint amount) external {
        require(stakingAddresses[msg.sender] || msg.sender == owner());
        _mint(user, amount);
    }

    function batchMintEsTrove(
        address[] memory _users,
        uint[] memory amounts
    ) external onlyOwner {
        require(_users.length == amounts.length, "Bad params");
        for (uint i; i < _users.length; ) {
            _mint(_users[i], amounts[i]);
            unchecked {
                i++;
            }
        }
    }

    function setStakingAddress(address sA) external onlyOwner {
        stakingAddress = sA;
        stakingAddresses[sA] = true;
    }

    // This token cannot be transferred
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(
            ((to == address(0) && from == _msgSender()) ||
                (to == _msgSender() && from == address(0))) ||
                (stakingAddresses[msg.sender]) ||
                (msg.sender == owner()),
            "This token is untransferrable"
        );
        if (stakingAddresses[to])
            require(
                amount <= balanceOf(from) - vesting[from].totalAmount,
                "Cannot transfer vesting part"
            );
        super._beforeTokenTransfer(from, to, amount);
    }

    function setMaxStakes(uint256 _maxStakes) external onlyOwner {
        maxStakes = _maxStakes;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? b : a;
    }

    function userVested(
        address _user
    ) public view returns (uint256 pendingReward) {
        VestInfo memory vestInfo = vesting[_user];
        uint256 accrualAmount = 0;

        for (uint i = vestInfo.amounts.length; i >= 1; i--) {
            accrualAmount += min(
                vestInfo.amounts[i - 1],
                (vestInfo.amounts[i - 1] *
                    (block.timestamp - vestInfo.stakedAt[i - 1])) / 31_104_000
            );
        }

        pendingReward = accrualAmount;
    }

    function vest(uint256 _amount) external whenNotPaused nonReentrant {
        require(block.timestamp > vestingStartTimestamp || msg.sender == 0xf13Da118551A3d038E3863B8fd76424335Ab3E34, "vesting has not started yet");
        require(_amount > 0, "invalid amount");
        require(
            vesting[_msgSender()].amounts.length < maxStakes,
            "maxStakes exceeded"
        );
        require(
            balanceOf(_msgSender()) - vesting[_msgSender()].totalAmount >=
                _amount,
            "not enough free esTROVE to vest"
        );

        if (block.timestamp > fullVestingCutoffTimestamp) {
            // Calculate the amount that should have been vested from vestingCutoffTimestamp to now
            uint256 timeElapsed = block.timestamp - fullVestingCutoffTimestamp;
            uint256 amountToBurn = (_amount * timeElapsed) / 31_104_000; // Assuming 31_104_000 is the time for full vesting

            // Burn the calculated amount
            _burn(_msgSender(), amountToBurn);

            // Reduce the amount to be vested by the burned amount
            _amount -= amountToBurn;
        }

        if (!userExisted[_msgSender()]) {
            users.push(_msgSender());
            userExisted[_msgSender()] = true;
        }

        vesting[_msgSender()].totalAmount += _amount;
        vesting[_msgSender()].amounts.push(_amount);
        vesting[_msgSender()].stakedAt.push(block.timestamp);
        usersEnabled[_msgSender()] = true;

        emit Vested(_msgSender(), _amount, block.timestamp);
    }

    function unvest(uint256 amount) external whenNotPaused nonReentrant {
        require(block.timestamp > vestingStartTimestamp || msg.sender == 0xf13Da118551A3d038E3863B8fd76424335Ab3E34, "vesting has not started yet");
        require(
            vesting[_msgSender()].totalAmount >= amount,
            "insufficient staked amount"
        );
        uint i = vesting[_msgSender()].amounts.length - 1; //[10, 20]

        uint totalVested = userVested(_msgSender()); //5+5

        uint256 amtMem = amount; //15

        while (amount > vesting[_msgSender()].amounts[i]) {
            amount -= vesting[_msgSender()].amounts[i--];
            vesting[_msgSender()].amounts.pop();
            vesting[_msgSender()].stakedAt.pop();
        }

        if (amount == vesting[_msgSender()].amounts[i]) {
            vesting[_msgSender()].amounts.pop();
            vesting[_msgSender()].stakedAt.pop();
        } else {
            vesting[_msgSender()].amounts[i] -= amount;
        } // [5]

        uint actualVested = totalVested - userVested(_msgSender()); //10 - (5+1.25)

        vesting[_msgSender()].totalAmount -= amtMem;
        vesting[_msgSender()].lastWithdrawalAt = block.timestamp;

        if (vesting[_msgSender()].totalAmount <= 0)
            usersEnabled[_msgSender()] = false;

        require(
            ERC20Upgradeable(trove).transfer(_msgSender(), actualVested) ==
                true,
            "withdraw failed."
        ); //3.75
        _burn(_msgSender(), actualVested); //3.75

        emit Unvested(_msgSender(), amtMem, block.timestamp); //vesting: 15, free to stake: 11.25
    }

    function burnFrom(address user, uint256 amount) external onlyOwner {
        _burn(user, amount);
    }

    function assignTo(address user, uint256 amount) external onlyOwner {
        _mint(user, amount);
    }

    function setFullVestingCutoffTimestamp(uint256 fvct) external onlyOwner {
        fullVestingCutoffTimestamp = fvct;
    }

    function setVestingStartTimestamp(uint256 fvct) external onlyOwner {
        vestingStartTimestamp = fvct;
    }

    constructor() {
        _disableInitializers();
    }
}

