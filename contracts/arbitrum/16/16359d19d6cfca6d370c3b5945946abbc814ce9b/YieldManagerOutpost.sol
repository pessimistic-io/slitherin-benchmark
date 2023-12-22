// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";

contract YieldManagerOutpost is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public owner;
    mapping(address => address) public affiliateLookup;
    mapping(address => bool) public setAffiliateFactorAddress;
    mapping(address => bool) public canSetSponsor;
    mapping(address => uint) public userLevel;

    event AffiliateSet(address indexed sponsor, address indexed client);
    event NewOwner(address owner);
    event NewCanSetSponsor(address canSet, bool status);
    event VestingSet(address client, address vesting);
    event SetAffiliateFactorAddressUpdated(address setAffiliateFactorAddress, bool allowed);
    event UserLevelSet(address user, uint level);

    // struct configStruct
    // val1 client:  withdrawal fee sponsor: % of fee
    struct configStruct {
        uint level;
        uint val1;
        uint val2;
        uint val3;
        uint val4;
    }

    configStruct[] public clientLevels;
    configStruct[] public sponsorLevels;

    // only owner modifier
    modifier onlyOwner {
        _onlyOwner();
        _;
    }

    // only owner view
    function _onlyOwner() private view {
        require(msg.sender == owner, "Only the contract owner may perform this action");
    }

    constructor() {
        owner = msg.sender;
        //set client levels initial
        clientLevels.push(
            configStruct({
                level: 0,
                val1: 0,
                // performance fee
                val2: 1500,
                // mgmt fee
                val3: 100,
                // mgmt fee fixed
                val4: 200
            })
        );
        clientLevels.push(
            configStruct({
                level: 1,
                val1: 0,
                val2: 1250,
                val3: 100,
                val4: 200
            })
        );
        clientLevels.push(
            configStruct({
                level: 2,
                val1: 0,
                val2: 1000,
                val3: 100,
                val4: 200
            })
        );
        clientLevels.push(
            configStruct({
                level: 3,
                val1: 0,
                val2: 750,
                val3: 75,
                val4: 125
            })
        );
        clientLevels.push(
            configStruct({
                level: 4,
                val1: 0,
                val2: 500,
                val3: 75,
                val4: 125
            })
        );

        //set sponsor levels initial
        sponsorLevels.push(
            configStruct({
                level: 0,
                val1: 0,
                val2: 0,
                val3: 0,
                val4: 0
            })
        );
        sponsorLevels.push(
            configStruct({
                level: 1,
                val1: 1000,
                val2: 1500,
                val3: 0,
                val4: 0
            })
        );
        sponsorLevels.push(
            configStruct({
                level: 2,
                val1: 1500,
                val2: 2500,
                val3: 0,
                val4: 0
            })
        );
        sponsorLevels.push(
            configStruct({
                level: 3,
                val1: 2000,
                val2: 5000,
                val3: 0,
                val4: 0
            })
        );
        sponsorLevels.push(
            configStruct({
                level: 4,
                val1: 2500,
                val2: 7500,
                val3: 0,
                val4: 0
            })
        );
    }

    //updates client levels
    function setClientLevels(uint[] memory levels, uint[] memory val1s, uint[] memory val2s, uint[] memory val3s, uint[] memory val4s) public onlyOwner {
        require(levels.length == val1s.length, "length mismatch");
        require(val1s.length == val2s.length, "length mismatch");
        require(val2s.length == val3s.length, "length mismatch");
        require(val3s.length == val4s.length, "length mismatch");
        delete clientLevels;

        for (uint i=0; i<levels.length; i++) {
            clientLevels.push(
                configStruct({
                    level: levels[i],
                    val1: val1s[i],
                    val2: val2s[i],
                    val3: val3s[i],
                    val4: val4s[i]
            })
            );
        }
    }

    //updates client levels
    function setSponsorLevels(uint[] memory levels, uint[] memory val1s, uint[] memory val2s, uint[] memory val3s, uint[] memory val4s) public onlyOwner {
        require(levels.length == val1s.length, "length mismatch");
        require(val1s.length == val2s.length, "length mismatch");
        require(val2s.length == val3s.length, "length mismatch");
        require(val3s.length == val4s.length, "length mismatch");
        delete sponsorLevels;

        for (uint i=0; i<levels.length; i++) {
            sponsorLevels.push(
                configStruct({
                    level: levels[i],
                    val1: val1s[i],
                    val2: val2s[i],
                    val3: val3s[i],
                    val4: val4s[i]
            })
            );
        }
    }

    // returns sponsor
    function getAffiliate(address client) public view returns (address) {
        return affiliateLookup[client];
    }

    function setAffiliate(address client, address sponsor) public {
        require (canSetSponsor[msg.sender] == true, "not allowed to set sponsor");
        require(affiliateLookup[client] == address(0), "sponsor already set");
        affiliateLookup[client] = sponsor;
        emit AffiliateSet(sponsor, client);
    }

    function ownerSetAffiliate(address client, address sponsor) public {
        require(setAffiliateFactorAddress[msg.sender], "not allowed to set affiliate");
        affiliateLookup[client] = sponsor;
        emit AffiliateSet(sponsor, client);
    }

    function ownerSetUserLevel(address client, uint level) public {
        require(setAffiliateFactorAddress[msg.sender], "not allowed to set affiliate");
        userLevel[client] = level;
        emit UserLevelSet(client, level);
    }

    function getUserFactors(
        address user,
        uint typer
    ) public view returns (uint, uint, uint, uint) {
        uint level = userLevel[user];

        // if its for client
        if (typer == 0) {
            // check normal staking
            if (level == clientLevels[0].level) {
                return (
                    clientLevels[0].val1,
                    clientLevels[0].val2,
                    clientLevels[0].val3,
                    clientLevels[0].val4
                );
            } else if (
                level == clientLevels[1].level
            ) {
                return (
                    clientLevels[1].val1,
                    clientLevels[1].val2,
                    clientLevels[1].val3,
                    clientLevels[1].val4
                );
            } else if (
                level == clientLevels[2].level
            ) {
                return (
                    clientLevels[2].val1,
                    clientLevels[2].val2,
                    clientLevels[2].val3,
                    clientLevels[2].val4
                );
            } else if (
                level == clientLevels[3].level
            ) {
                return (
                    clientLevels[3].val1,
                    clientLevels[3].val2,
                    clientLevels[3].val3,
                    clientLevels[3].val4
                );
            } else {
                return (
                    clientLevels[4].val1,
                    clientLevels[4].val2,
                    clientLevels[4].val3,
                    clientLevels[4].val4
                );
            }
        }

        // else we calculate sponsor
        if (level < sponsorLevels[0].level) {
            return (
                sponsorLevels[0].val1,
                sponsorLevels[0].val2,
                sponsorLevels[0].val3,
                sponsorLevels[0].val4
            );
        } else if (
            level == sponsorLevels[1].level
        ) {
            return (
                sponsorLevels[1].val1,
                sponsorLevels[1].val2,
                sponsorLevels[1].val3,
                sponsorLevels[1].val4
            );
        } else if (
            level == sponsorLevels[2].level
        ) {
            return (
                sponsorLevels[2].val1,
                sponsorLevels[2].val2,
                sponsorLevels[2].val3,
                sponsorLevels[2].val4
            );
        } else if (
            level == sponsorLevels[3].level
        ) {
            return (
                sponsorLevels[3].val1,
                sponsorLevels[3].val2,
                sponsorLevels[3].val3,
                sponsorLevels[3].val4
            );
        } else {
            return (
                sponsorLevels[4].val1,
                sponsorLevels[4].val2,
                sponsorLevels[4].val3,
                sponsorLevels[4].val4
            );
        }
    }

    function newOwner(address newOwner_) external {
        require(msg.sender == owner, "Only factory owner");
        require(newOwner_ != address(0), "No zero address for newOwner");

        owner = newOwner_;
        emit NewOwner(owner);
    }

    function setCanSetSponsor(address factoryContract, bool val) external onlyOwner {
        canSetSponsor[factoryContract] = val;
        emit NewCanSetSponsor(factoryContract, val);
    }

    function setSetAffiliateFactorAddress(address setAddress, bool allowed) external onlyOwner {
        setAffiliateFactorAddress[setAddress] = allowed;
        emit SetAffiliateFactorAddressUpdated(setAddress, allowed);
    }
}

