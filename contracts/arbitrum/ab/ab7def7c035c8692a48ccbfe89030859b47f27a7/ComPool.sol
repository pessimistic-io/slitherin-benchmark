// SPDX-License-Identifier: GPL-3.0

pragma solidity =0.8.4;
import "./OwnableUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";

struct Allocation {
    string name;
    uint256 alloc;
}

contract ComPool is OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 private oneHundredPrecent;
    address public token;
    mapping(uint256 => Allocation) public allocations;
    uint256 public potentialLoss;

    function initialize(uint256 _oneHundredPrecent, address _token) public initializer {
        oneHundredPrecent = _oneHundredPrecent;
        token = _token;
        OwnableUpgradeable.__Ownable_init();
        allocations[0] = Allocation("Sport", (oneHundredPrecent * 80) / 100); // 80%
        allocations[1] = Allocation("Others", (oneHundredPrecent * 20) / 100); // 20%
        potentialLoss = (oneHundredPrecent * 2) / 100; // 2%
    }

    function approve(address _elpToken) public onlyOwner {
        uint256 _maxInt = 2**256 - 1;
        IERC20Upgradeable(token).approve(_elpToken, _maxInt);
    }

    /**
     * @dev Set pool allocation to game play
     */
    function setDistribution(string[] memory _names, uint256[] memory _allocs) public onlyOwner {
        require(_names.length == _allocs.length, "not-match-length");
        uint256 _totalAlloc = 0;
        for (uint256 i = 0; i < _allocs.length; i++) {
            _totalAlloc += _allocs[i];
            allocations[i].name = _names[i];
            allocations[i].alloc = _allocs[i];
        }
        require(_totalAlloc == oneHundredPrecent, "not-equal-hundred-percent");
    }

    function setPotentialLossPercent(uint256 _potentialLoss) public onlyOwner {
        potentialLoss = _potentialLoss;
    }

    /**
     * @dev Deposit to pool
     */
    function deposit(uint256 _amount) public {
        IERC20Upgradeable(token).safeTransferFrom(msg.sender, address(this), _amount);
    }

    /**
     * @dev Capacity of pool
     */
    function capacity() public view returns (uint256) {
        return IERC20Upgradeable(token).balanceOf(address(this));
    }

    /**
     * @dev Get pool allocation acoording to game play
     */
    function getAllocation(uint256 _idx) public view returns (uint256) {
        return (((capacity() * allocations[_idx].alloc) / oneHundredPrecent) * potentialLoss) / oneHundredPrecent;
    }
}

