// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./IERC20.sol";
import "./OFTUpgradeable.sol";

contract FbaTokenV2 is OFTUpgradeable {
    uint256 public constant DAY_0_TS = 1656201600; // Sunday, 26 June 2022 00:00:00 UTC

    mapping(address => uint256) public minterCap;
    mapping(address => uint256) public dailyMinterCap;
    mapping(address => uint256) public minterLastMintingDay; // user => last minting day index
    mapping(address => uint256) public minterTodayMintedAmount; // user => current day total minted amount
    mapping(address => uint256) public minterTotalAccumulatedMintedAmount; // user => total accumulated minted amount

    /* ========== Modifiers =============== */
    modifier onlyMinter() {
        require(minterCap[msg.sender] > 0 || dailyMinterCap[msg.sender] > 0, "!minter");
        _;
    }

    /* ========== GOVERNANCE ========== */
    function initialize(address _lzEndpoint) public initializer {
        __OFTUpgradeable_init("Firebird Aggregator", "FBA", _lzEndpoint);
    }

    function setMinterCap(address _account, uint256 _minterCap) external onlyOwner {
        require(_account != address(0), "zero");
        minterCap[_account] = _minterCap;
        emit MinterCapUpdate(_account, _minterCap);
    }

    function setDailyMinterCap(address _account, uint256 _dailyMinterCap) external onlyOwner {
        require(_account != address(0), "zero");
        dailyMinterCap[_account] = _dailyMinterCap;
        emit DailyMinterCapUpdate(_account, _dailyMinterCap);
    }

    /* ========== VIEW FUNCTIONS ========== */
    function getDayIndex() public view returns (uint256) {
        return (block.timestamp - DAY_0_TS) / 24 hours;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */
    function mint(address _recipient, uint _amount) external virtual onlyMinter {
        if (minterCap[msg.sender] >= _amount) {
            minterCap[msg.sender] -= _amount;
        } else {
            require(dailyMinterCap[msg.sender] >= _amount, "need minting or daily minting cap");
            uint256 _todayIndex = getDayIndex();
            if (_todayIndex > minterLastMintingDay[msg.sender]) {
                minterLastMintingDay[msg.sender] = _todayIndex;
                minterTodayMintedAmount[msg.sender] = _amount;
            } else {
                minterTodayMintedAmount[msg.sender] += _amount;
                require(minterTodayMintedAmount[msg.sender] <= dailyMinterCap[msg.sender], "exceed daily minting cap");
            }
        }
        minterTotalAccumulatedMintedAmount[msg.sender] += _amount;
        OFTUpgradeable._creditTo(0, _recipient, _amount);
    }

    function burn(uint256 _amount) external {
        burnFrom(msg.sender, _amount);
    }

    function burnFrom(address _account, uint256 _amount) public {
        OFTUpgradeable._debitFrom(_account, 0, "", _amount);
    }

    /* ========== EMERGENCY ========== */
    function governanceRecoverUnsupported(IERC20 _token) external onlyOwner {
        _token.transfer(owner(), _token.balanceOf(address(this)));
    }

    /* ========== EVENTS ========== */
    event MinterCapUpdate(address indexed account, uint256 cap);
    event DailyMinterCapUpdate(address indexed account, uint256 dailyCap);
}

