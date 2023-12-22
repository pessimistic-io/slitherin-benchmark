// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./Pausable.sol";
import "./ERC20_IERC20.sol";
import "./SafeERC20.sol";

import "./Referral.sol";
import "./NFT.sol";

contract IDO is Ownable, Pausable, Referral {
    using SafeERC20 for IERC20;

    IERC20 public usdt;
    IERC20 public agc;
    NFT public nft;
    address public team;

    uint256 public rate;
    uint256 public endTime;
    uint256 public totalUsdt;
    uint256 public totalAddress;

    struct PhaseInfo {
        uint256 startTime;
        uint256 price;
        uint256 amount;
    }

    struct AddressInfo {
        bool hasJoined;
        uint256 invite;
        uint256 blindBoxBalance;
        uint256 totalReward;
        uint256 rewardParent;
    }

    mapping(uint256 => PhaseInfo) public phaseInfos;
    mapping(address => AddressInfo) public addressInfos;

    constructor(address _usdt, address _agc, address _nft, address _team) Referral(_team) {
        usdt = IERC20(_usdt);
        agc = IERC20(_agc);
        nft = NFT(_nft);
        team = _team;

        addressInfos[_team].hasJoined = true;

        rate = 500;

        phaseInfos[1].price = 0.1 * 1e6;
        phaseInfos[1].amount = 100 * 1e6;

        phaseInfos[2].price = 0.12 * 1e6;
        phaseInfos[2].amount = 120 * 1e6;

        phaseInfos[3].price = 0.15 * 1e6;
        phaseInfos[3].amount = 150 * 1e6;
    }

    function setTeam(address account) public onlyOwner {
        team = account;
    }

    function phase() public view returns (uint256) {
        if (phaseInfos[1].startTime == 0) {
            return 0;
        }
        uint256 time = block.timestamp;
        if (time < phaseInfos[1].startTime) {
            return 0;
        } else if (time >= phaseInfos[1].startTime && time < phaseInfos[2].startTime) {
            return 1;
        } else if (time >= phaseInfos[2].startTime && time < phaseInfos[3].startTime) {
            return 2;
        } else if (time >= phaseInfos[3].startTime && time < endTime) {
            return 3;
        } else {
            return 4;
        }
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function setRate(uint256 _rate) external onlyOwner {
        rate = _rate;
    }

    function setTime(uint256 _time) external onlyOwner {
        phaseInfos[1].startTime = _time;
        phaseInfos[2].startTime = _time + 7 days;
        phaseInfos[3].startTime = _time + 14 days;
        endTime = _time + 21 days;
    }

    function setAmount(uint256 _amount, uint256 _phase) external onlyOwner {
        if (_phase < 1 || _phase > 3) revert();
        phaseInfos[_phase].amount = _amount;
    }

    function setPrice(uint256 _price, uint256 _phase) external onlyOwner {
        if (_phase < 1 || _phase > 3) revert();
        phaseInfos[_phase].price = _price;
    }

    function ido(address _parent) external whenNotPaused {
        uint256 _phase = phase();
        if (_phase < 1 || _phase > 3) revert();
        if (addressInfos[msg.sender].hasJoined == true) revert();
        if (addressInfos[_parent].hasJoined == false) revert();
        _register(_parent);

        usdt.safeTransferFrom(msg.sender, team, phaseInfos[_phase].amount);

        uint256 amount = (phaseInfos[_phase].amount / phaseInfos[_phase].price) * 1e18;
        agc.safeTransfer(msg.sender, amount);

        uint256 reward = (amount * rate) / 10000;
        agc.safeTransfer(_parent, reward);

        addressInfos[msg.sender].hasJoined = true;
        addressInfos[msg.sender].rewardParent = reward;

        addressInfos[_parent].invite++;
        addressInfos[_parent].totalReward += reward;

        if (addressInfos[_parent].invite % 10 == 0) {
            addressInfos[_parent].blindBoxBalance++;
        }

        totalUsdt += phaseInfos[_phase].amount;
        totalAddress++;
    }

    function open() external whenNotPaused {
        addressInfos[msg.sender].blindBoxBalance--;
        nft.safeMint(msg.sender);
    }
}

