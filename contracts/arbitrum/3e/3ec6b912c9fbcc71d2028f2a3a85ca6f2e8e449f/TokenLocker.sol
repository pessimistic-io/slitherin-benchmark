// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { Initializable } from "./Initializable.sol";
import { IERC20Upgradeable } from "./IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "./SafeERC20Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";

import { ITokenLocker } from "./ITokenLocker.sol";

contract TokenLocker is Initializable, ReentrancyGuardUpgradeable, ITokenLocker {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct Global {
        address token;
        uint256 duration;
        uint256 startTime;
        uint256 totalSupply;
        uint256 totalClaimed;
        bool initialized;
    }

    uint256 public poolCount;
    uint256 public totalOwners;

    Global public g;

    mapping(address => bool) public owners;
    mapping(address => uint256) public userLocked;
    mapping(address => uint256) public userStartTime;
    mapping(address => uint256) public userClaimed;
    mapping(address => uint256) public disabledAt;

    event NewOwner(address indexed _sender, address _owner);
    event RemoveOwner(address indexed _sender, address _owner);

    event AddFund(address _recipients, uint256 _amounts);
    event ToggleDisable(address _recipient, bool _disabled);
    event Claim(address _recipient, uint256 _claimed);

    modifier onlyOwners() {
        require(isOwner(msg.sender), "TokenLocker: Caller is not an owner");
        _;
    }

    // @custom:oz-upgrades-unsafe-allow constructor
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    /// @notice used to initialize the contract
    function initialize(address _owner) external initializer {
        require(_owner != address(0), "TokenLocker: _owner cannot be 0x0");

        owners[_owner] = true;
        totalOwners++;
    }

    function setGlobal(address _token, uint256 _duration, uint256 _startTime) public onlyOwners {
        require(g.initialized == false, "TokenLocker: Cannot run this function twice");

        g.token = _token;
        g.duration = _duration;
        g.startTime = _startTime;
        g.totalSupply = 0;
        g.totalClaimed = 0;
        g.initialized = true;
    }

    function updateDuration(uint256 _duration) public onlyOwners {
        require(g.startTime == 0, "TokenLocker: The contract does not support");

        g.duration = _duration;
    }

    /// @notice add owner
    /// @param _newOwner owner address
    function addOwner(address _newOwner) public onlyOwners {
        require(_newOwner != address(0), "TokenLocker: _newOwner cannot be 0x0");
        require(!isOwner(_newOwner), "TokenLocker: _newOwner is already owner");

        owners[_newOwner] = true;
        totalOwners++;

        emit NewOwner(msg.sender, _newOwner);
    }

    /// @notice add owners
    /// @param _newOwners owners array
    function addOwners(address[] calldata _newOwners) external onlyOwners {
        for (uint256 i = 0; i < _newOwners.length; i++) {
            addOwner(_newOwners[i]);
        }
    }

    /// @notice remove owner
    /// @param _owner owner address
    function removeOwner(address _owner) external onlyOwners {
        require(_owner != address(0), "TokenLocker: _owner cannot be 0x0");
        require(isOwner(_owner), "TokenLocker: _owner is not an owner");
        require(totalOwners > 1, "TokenLocker: totalOwners must be greater than 1");

        owners[_owner] = false;
        totalOwners--;

        emit RemoveOwner(msg.sender, _owner);
    }

    /// @notice judge if its owner
    /// @param _owner owner address
    /// @return bool value
    function isOwner(address _owner) public view returns (bool) {
        return owners[_owner];
    }

    function addFund(address _recipient, uint256 _amountIn) public override onlyOwners {
        {
            uint256 before = IERC20Upgradeable(g.token).balanceOf(address(this));
            IERC20Upgradeable(g.token).safeTransferFrom(msg.sender, address(this), _amountIn);
            _amountIn = IERC20Upgradeable(g.token).balanceOf(address(this)) - before;
        }

        userLocked[_recipient] += _amountIn;
        g.totalSupply += _amountIn;

        if (g.startTime == 0) {
            userStartTime[_recipient] = block.timestamp;
        } else {
            userStartTime[_recipient] = g.startTime;
        }

        emit AddFund(_recipient, _amountIn);
    }

    function addFunds(address[] calldata _recipients, uint256[] calldata _amounts, uint256 _totalSupply) public override onlyOwners {
        require(_recipients.length == _amounts.length, "TokenLocker: Length mismatch");

        {
            uint256 before = IERC20Upgradeable(g.token).balanceOf(address(this));
            IERC20Upgradeable(g.token).safeTransferFrom(msg.sender, address(this), _totalSupply);
            _totalSupply = IERC20Upgradeable(g.token).balanceOf(address(this)) - before;
        }

        for (uint256 i = 0; i < _recipients.length; i++) {
            require(_totalSupply >= _amounts[i], "TokenLocker: Not enough amounts");

            _totalSupply -= _amounts[i];
            g.totalSupply += _amounts[i];
            userLocked[_recipients[i]] += _amounts[i];

            if (g.startTime == 0) {
                userStartTime[_recipients[i]] = block.timestamp;
            } else {
                userStartTime[_recipients[i]] = g.startTime;
            }

            emit AddFund(_recipients[i], _amounts[i]);
        }

        if (_totalSupply > 0) {
            IERC20Upgradeable(g.token).safeTransfer(msg.sender, _totalSupply);
        }
    }

    function toggleDisable(address _recipient) external onlyOwners {
        bool disabled = disabledAt[_recipient] > 0;

        if (disabled) {
            disabledAt[_recipient] = 0;
        } else {
            disabledAt[_recipient] = block.timestamp;
        }

        emit ToggleDisable(_recipient, disabled);
    }

    function claim() external override nonReentrant {
        uint256 claimed = _availableOf(msg.sender);

        g.totalClaimed += claimed;
        userClaimed[msg.sender] += claimed;

        IERC20Upgradeable(g.token).safeTransfer(msg.sender, claimed);

        emit Claim(msg.sender, claimed);
    }

    function _totalBalanceOf(address _recipient, uint256 _t) internal view returns (uint256) {
        uint256 locked = userLocked[_recipient];
        uint256 startTime = userStartTime[_recipient];

        if (_t < userStartTime[_recipient]) {
            return 0;
        }

        return _min((locked * (_t - startTime)) / (_endTime(startTime, g.duration) - startTime), locked);
    }

    function _availableOf(address _recipient) internal view returns (uint256) {
        uint256 t = disabledAt[_recipient];

        if (t == 0) {
            t = block.timestamp;
        }

        return _totalBalanceOf(_recipient, t) - userClaimed[_recipient];
    }

    function vestedSupply() external view returns (uint256) {
        require(g.startTime > 0, "TokenLocker: The contract does not support");

        if (block.timestamp <= g.startTime) {
            return 0;
        }

        return _min((g.totalSupply * (block.timestamp - g.startTime)) / (_endTime(g.startTime, g.duration) - g.startTime), g.totalSupply);
    }

    function totalSupply() external view returns (uint256) {
        return g.totalSupply - g.totalClaimed;
    }

    function availableOf(address _recipient) external view returns (uint256) {
        return _availableOf(_recipient);
    }

    function lockedOf(address _recipient) external view returns (uint256) {
        return userLocked[_recipient] - _totalBalanceOf(_recipient, block.timestamp);
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _endTime(uint256 _startTime, uint256 _duration) internal pure returns (uint256) {
        return _startTime + _duration;
    }
}

