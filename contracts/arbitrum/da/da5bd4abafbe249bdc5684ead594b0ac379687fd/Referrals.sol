// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// external
import "./SafeERC20Upgradeable.sol";
import "./MathUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./SafeMathUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./PausableUpgradeable.sol";
import "./Clones.sol";

// internal
import "./ProxyReentrancyGuard.sol";
import "./ProxyOwned.sol";
import "./ProxyPausable.sol";
import "./AddressSetLib.sol";

contract Referrals is Initializable, ProxyOwned, ProxyPausable, ProxyReentrancyGuard {
    mapping(address => bool) public whitelistedAddresses;
    mapping(address => address) public referrals;
    mapping(address => uint) public referralStarted;

    mapping(address => bool) public tradedBefore;
    
    mapping(address => address) public sportReferrals;
    mapping(address => uint) public sportReferralStarted;
    mapping(address => bool) public sportTradedBefore;
    address public sportsAMM;

    function initialize(
        address _owner,
        address thalesAmm,
        address rangedAMM
    ) public initializer {
        setOwner(_owner);
        initNonReentrant();
        whitelistedAddresses[thalesAmm] = true;
        whitelistedAddresses[rangedAMM] = true;
    }

    function setReferrer(address referrer, address referred) external {
        require(referrer != address(0) && referred != address(0), "Cant refer zero addresses");
        require(referrer != referred, "Cant refer to yourself");
        require(
            whitelistedAddresses[msg.sender] || owner == msg.sender,
            "Only whitelisted addresses or owner set referrers"
        );
        if(msg.sender == sportsAMM) {
            if (!sportTradedBefore[referred] && sportReferrals[referred] == address(0)) {
                sportReferrals[referred] = referrer;
                sportReferralStarted[referred] = block.timestamp;
                emit SportReferralAdded(referrer, referred, block.timestamp);
            }
        }
        else {
            if (!tradedBefore[referred] && referrals[referred] == address(0)) {
                referrals[referred] = referrer;
                referralStarted[referred] = block.timestamp;
                emit ReferralAdded(referrer, referred, block.timestamp);
            }
        }
    }

    function setWhitelistedAddress(address _address, bool enabled) external onlyOwner {
        require(whitelistedAddresses[_address] != enabled, "Address already enabled/disabled");
        whitelistedAddresses[_address] = enabled;
        emit SetWhitelistedAddress(_address, enabled);
    }

    function setTradedBefore(address[] calldata _addresses) external onlyOwner {
        for (uint256 index = 0; index < _addresses.length; index++) {
            tradedBefore[_addresses[index]] = true;
            emit TradedBefore(_addresses[index]);
        }
    }
    function setSportTradedBefore(address[] calldata _addresses) external onlyOwner {
        for (uint256 index = 0; index < _addresses.length; index++) {
            sportTradedBefore[_addresses[index]] = true;
            emit SportTradedBefore(_addresses[index]);
        }
    }

    function setSportsAMM(address _sportsAMM) external onlyOwner {
        require(!whitelistedAddresses[_sportsAMM], "Address already enabled");
        whitelistedAddresses[sportsAMM] = false;
        whitelistedAddresses[_sportsAMM] = true;
        sportsAMM = _sportsAMM;
        emit SetWhitelistedAddress(_sportsAMM, true);
    }

    event SportReferralAdded(address referrer, address referred, uint timeStarted);
    event ReferralAdded(address referrer, address referred, uint timeStarted);
    event TradedBefore(address trader);
    event SportTradedBefore(address trader);
    event SetWhitelistedAddress(address whitelisted, bool enabled);
}

