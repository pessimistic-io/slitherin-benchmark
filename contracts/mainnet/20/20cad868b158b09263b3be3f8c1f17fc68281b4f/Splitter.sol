// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// Import this file to use console.log
import "./console.sol";
import "./IERC20.sol";

contract SalesDAOSplitter {
    IERC20 DAI;
    address public owner;
    address public _daoAddress;
    address[] public _founders;
    address _daiAddress = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    uint256 public _heldDai;
    uint256 public _heldEth;
    uint256 public DAOBPS = 650;
    uint256 public FOUNDERBPS = 300;
    bool guard;

    event PaymentReceived(address from, uint256 amount, string currency);
    event PayoutCompleted(address to, uint256 amount, string currency);

    constructor() {
        DAI = IERC20(_daiAddress);
        owner = msg.sender;
        _daoAddress = 0xef107eEf75a2efaa93a21500524A79904A0a5Cf7;
        _founders.push(0xb62F6C399bA1A505d0874150F4336B7Ed403bA38);
        _founders.push(0x9c83764cdDEC7D090268ba1c92E5D4819E920Bc7);
        guard = false;
    }

    function changeBPS(uint256 _daoBPS, uint256 _founderBPS) external {
        require(
            (msg.sender == owner || msg.sender == _daoAddress),
            "only owner can change BPS"
        );
        DAOBPS = _daoBPS;
        FOUNDERBPS = _founderBPS;
    }

    function changeDaoAddress(address daoAddress) external {
        require(
            (msg.sender == owner || msg.sender == daoAddress),
            "only owner can change dao address"
        );
        _daoAddress = daoAddress;
    }

    function changeFounders(address[] memory founders) external {
        require(
            (msg.sender == owner || msg.sender == _daoAddress),
            "only owner can change founders"
        );
        _founders = founders;
    }

    function calculateSplits(uint256 _amount)
        public
        view
        returns (uint256[] memory)
    {
        uint256[] memory splits = new uint256[](_founders.length + 1);
        uint256 daoAmount = (_amount * DAOBPS) / 10000;
        splits[0] = daoAmount;
        uint256 founderAmount = (_amount * FOUNDERBPS) / 10000;
        // each founder gets founderAmount
        uint256 runningRemainder = _amount - daoAmount;
        for (uint256 i = 1; i < _founders.length + 1; i++) {
            splits[i] = founderAmount;
            runningRemainder -= founderAmount;
            require(runningRemainder >= 0, "running remainder is negative");
        }
        // [6.5, 3, 3, ?, ?, ?];
        return splits;
    }

    function payWithDai(uint256 daiAmount, address recipient) external {
        guard = true;
        bool success = DAI.transferFrom(msg.sender, address(this), daiAmount);
        require(success, "input transfer failed");
        uint256 runningTotal = daiAmount;
        emit PaymentReceived(msg.sender, runningTotal, "DAI");
        _heldDai += runningTotal;
        uint256[] memory splits = calculateSplits(daiAmount);
        bool daoPayoutBool = DAI.transferFrom(
            address(this),
            _daoAddress,
            splits[0]
        );
        require(daoPayoutBool, "dao payout failed");
        emit PayoutCompleted(_daoAddress, splits[0], "DAI");
        _heldDai -= splits[0];
        runningTotal -= splits[0];
        for (uint256 i = 1; i < _founders.length + 1; i++) {
            bool founderPayout = DAI.transferFrom(
                address(this),
                _founders[i - 1],
                splits[i]
            );
            require(founderPayout, "founder payout failed");
            _heldDai -= splits[i];
            runningTotal -= splits[i];
            emit PayoutCompleted(_founders[i - 1], splits[i], "DAI");
        }
        bool recipientPayout = DAI.transferFrom(
            address(this),
            recipient,
            runningTotal
        );
        require(recipientPayout, "recipient payout failed");
        emit PayoutCompleted(recipient, runningTotal, "DAI");
        guard = false;
    }

    function withdrawDai() external {
        require(!guard, "cannot withdraw while splitting");
        require(
            (msg.sender == owner || msg.sender == _daoAddress),
            "only owner can withdraw"
        );
        bool success = DAI.transferFrom(address(this), msg.sender, _heldDai);
        require(success, "withdrawal failed");
        _heldDai = 0;
    }
}

