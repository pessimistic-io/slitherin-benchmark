// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./OwnableUpgradeable.sol";

contract Prox_IDO is OwnableUpgradeable {
    IERC20 public usdt;
    IERC20 public prox;
    uint price;//0.001 * 1e6
    uint public defaultAmount;

    struct UserInfo {
        bool isWhite;
        uint buyAmount;
        uint firstRank;
        uint secondRank;
        bool isClaimed;
    }

    mapping(address => UserInfo) public userInfo;
    mapping(address => bool) public superAccount;
    uint public whiteRank;
    uint public publicRank;

    struct TimeInfo {
        uint whiteStartTime;
        uint whiteEndTime;
        uint publicStartTime;
        uint publicEndTime;
        uint claimTime;
    }

    TimeInfo public timeInfo;
    uint public totalUAmount;
    uint public buyAmount;
    uint public modeSet;
    uint public returnUAmount;

    address public wallet;
    uint totalBuyAmount;

    event BuyIDO(address indexed addr, uint indexed amount);
    event Claim(address indexed addr, uint indexed amount);
    modifier onlyEOA(){
        require(msg.sender == tx.origin, 'not allowed');
        _;
    }

    function initialize() public initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
        totalUAmount = 30000e6;
        price = 1e3;
        defaultAmount = 100e6;
    }

    function setSuperAccount(address[] calldata _addr, bool _status) external onlyOwner {
        for (uint i = 0; i < _addr.length; i++) {
            superAccount[_addr[i]] = _status;
        }
    }

    function setUserWhite(address[] calldata addrs, bool b) external onlyOwner {
        for (uint i = 0; i < addrs.length; i++) {
            userInfo[addrs[i]].isWhite = b;
        }
    }

    function setWallet(address wallet_) external onlyOwner {
        wallet = wallet_;
    }

    function setMode(uint mode_) external onlyEOA {
        require(mode_ == 1 || mode_ == 2, 'mode error');
        modeSet = mode_;
    }

    function setToken(address prox_, address usdt_) external onlyOwner {
        prox = IERC20(prox_);
        usdt = IERC20(usdt_);
    }

    function setTime(uint whiteStartTime_, uint whiteEndTime_, uint publicStartTime_, uint publicEndTime_, uint claimTime_) external onlyOwner {
        timeInfo.whiteStartTime = whiteStartTime_;
        timeInfo.whiteEndTime = whiteEndTime_;
        timeInfo.publicStartTime = publicStartTime_;
        timeInfo.publicEndTime = publicEndTime_;
        timeInfo.claimTime = claimTime_;
    }

    function getAmountOut(uint uAmount) public view returns (uint){
        uint out = uAmount * 1e18 / price;
        return out;
    }

//    function setUserRank(uint round, address[] calldata addrs, uint rank) external onlyOwner {
//        if (round == 1) {
//            for (uint i = 0; i < addrs.length; i++) {
//                userInfo[addrs[i]].firstRank = rank;
//            }
//        } else {
//            for (uint i = 0; i < addrs.length; i++) {
//                userInfo[addrs[i]].secondRank = rank;
//            }
//        }
//    }

    function buyIDO() external onlyEOA {
        uint _timeNow = block.timestamp;
        require(_timeNow >= timeInfo.whiteStartTime && _timeNow < timeInfo.publicEndTime, 'out of time');
        require(wallet != address(0), 'wallet not set');
        if (_timeNow >= timeInfo.whiteStartTime && _timeNow < timeInfo.whiteEndTime) {
            whiteRank++;
            require(userInfo[msg.sender].firstRank == 0, 'already buy');
            require(userInfo[msg.sender].isWhite, 'not white');
            //            require(userInfo[msg.sender].buyAmount == 0, 'already buy');
            usdt.transferFrom(msg.sender, wallet, defaultAmount);
            userInfo[msg.sender].buyAmount += defaultAmount;
            buyAmount += defaultAmount;
            userInfo[msg.sender].firstRank = whiteRank;
            if (whiteRank > 150) {
                returnUAmount += defaultAmount;
            }
        }
        if (_timeNow >= timeInfo.publicStartTime && _timeNow < timeInfo.publicEndTime) {
            publicRank++;
            require(userInfo[msg.sender].secondRank == 0, 'already buy');
            if (!userInfo[msg.sender].isWhite) {
                require(userInfo[msg.sender].buyAmount == 0, 'already buy');
            }
            usdt.transferFrom(msg.sender, wallet, defaultAmount);
            userInfo[msg.sender].buyAmount += defaultAmount;
            buyAmount += defaultAmount;
            userInfo[msg.sender].secondRank = publicRank;
            if (publicRank > 150) {
                returnUAmount += defaultAmount;
            }

        }
        totalBuyAmount++;
        emit BuyIDO(msg.sender, defaultAmount);
    }

    function claim() external onlyEOA {
        require(!userInfo[msg.sender].isClaimed, 'already claimed');
        if (superAccount[msg.sender]) {
            uint temp = getAmountOut(defaultAmount);
            prox.transfer(msg.sender, temp);
            userInfo[msg.sender].isClaimed = true;
            emit Claim(msg.sender, temp);
            return;
        }

        require(modeSet == 1 || modeSet == 2, 'not set mode');
        require(block.timestamp >= timeInfo.claimTime, 'not claim time');
        require(userInfo[msg.sender].buyAmount != 0, 'no buy amount');
        uint tokenAmount;
        uint uAmount;
        (tokenAmount, uAmount) = calculateClaimAmount(msg.sender);
        require(tokenAmount > 0 || uAmount > 0, 'nothing to claim');
        if (tokenAmount > 0) {
            prox.transfer(msg.sender, tokenAmount);
        }
        if (uAmount > 0) {
            usdt.transfer(msg.sender, uAmount);
        }
        userInfo[msg.sender].isClaimed = true;
        emit Claim(msg.sender, tokenAmount);

    }

    function calculateClaimAmount(address addr) public view returns (uint tokenAmount, uint uAmount){
        tokenAmount = 0;
        uAmount = 0;

        if (modeSet == 1) {
            if (userInfo[addr].firstRank > 150) {
                uAmount += defaultAmount;
                tokenAmount = 0;
            }
            if (userInfo[addr].firstRank <= 150 && userInfo[addr].firstRank > 0) {
                uAmount += 0;
                tokenAmount += getAmountOut(defaultAmount);
            }
            if (userInfo[addr].secondRank > 150) {
                uAmount += defaultAmount;
                tokenAmount += 0;
            }
            if (userInfo[addr].secondRank <= 150 && userInfo[addr].secondRank > 0) {
                uAmount += 0;
                tokenAmount += getAmountOut(defaultAmount);
            }

        }
        if (modeSet == 2) {
            uAmount = 0;
            tokenAmount = getAmountOut(userInfo[addr].buyAmount);
        }
        return (tokenAmount, uAmount);

    }


}
