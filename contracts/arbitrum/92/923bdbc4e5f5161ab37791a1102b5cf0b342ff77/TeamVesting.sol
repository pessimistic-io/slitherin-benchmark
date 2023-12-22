// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./IERC20.sol";

contract TeamVesting {
    IERC20 public immutable token;
    uint256 public constant vestingPeriod = 548 days;
    mapping(address => uint256) public allocation;
    mapping(address => uint256) public claimed;
    uint256 public start;
    bool public started;

    constructor(address _token, address[] memory _wallet, uint256[] memory _allocation) {
        require(_wallet.length == 4 && _allocation.length == 4, "length");
        require(_token != address(0), "ZeroAddress");
        token = IERC20(_token);
        for (uint256 i=0; i<_wallet.length; i++) {
            allocation[_wallet[i]] = _allocation[i];
        }
    }

    function startSwap() external {
        require(!started, "Started");
        require(block.timestamp >= 1677009600, "Too early to start"); // Tue Feb 21 2023 20:00:00 UTC
        started = true;
        start = block.timestamp;
    }

    function claim() external {
        require(started, "!Started");
        uint256 _claimable = claimable(msg.sender);
        require(_claimable > 0, "Nothing to claim");
        claimed[msg.sender] += _claimable;
        token.transfer(msg.sender, _claimable);
    }

    function claimable(address _wallet) public view returns (uint256) {
        if (!started) return 0;
        if (block.timestamp - start > vestingPeriod)
            return allocation[_wallet] - claimed[_wallet];
        return (allocation[_wallet] * (block.timestamp - start)) / vestingPeriod - claimed[_wallet];
    }
}
