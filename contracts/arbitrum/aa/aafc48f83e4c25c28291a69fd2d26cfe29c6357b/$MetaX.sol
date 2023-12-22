// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./ERC20.sol";
import "./IMetaX.sol";
import "./AccessControl.sol";
import "./Ownable.sol";

contract $MetaX is ERC20, AccessControl, Ownable {

/** Roles **/
    bytes32 public constant Admin = keccak256("Admin");

    bytes32 public constant Burner = keccak256("Burner");

    constructor(
        uint256 _T0
    ) ERC20("MetaX", "MetaX") {
        T0 = _T0;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(Admin, msg.sender);
    }

/** Token Allocation **/

    /* Vaults by MetaX Smart Contracts */
    address[] public Vaults = [
        0xB5ec8e0b6C8f20ba344CD3d0eaA890dF6D0Bf7c4, /* #0 Social Mining 40% */
        0x6A3bB40902C6B25ce8cbeFcD1E717f39De064Cb7, /* #1 Builder Incentives 5% */
        0x00056aFf95b8B46ecA059c622a891E095792Dd47, /* #2 Marketing Expense 10% */
        0x5a49E4c0549A31bfD728fFe8577C81c87624760e, /* #3 Treasure 10% */
        0xEeB56e83fc333c3555ff8b9e64973113Db36CeCf, /* #4 Team Reserved 15% */
        0x35Ebdf5dF44CbCc6007CBB6E2Cfdc4D5dD1Db961, /* #5 Advisors 5% */
        0x49B7c5Eb4Ee5b72F10D4B8E242dA7598aC0e657C  /* #6 Investors 15% */
    ];

    function setVaults(uint256 batch, address _Vault) public onlyOwner {
        Vaults[batch] = _Vault;
    }

    /* Tokens Allocation */
    uint256 public immutable Max = 20000000000 ether;

    function maxSupply() external view returns (uint256) {
        return Max - numberBurnt;
    }

    uint256[] public Allocation = [
        8000000000 ether, /* #0 Social Mining 40% */
        1000000000 ether, /* #1 Builder Incentives 5% */
        2000000000 ether, /* #2 Marketing Expense 10% */
        2000000000 ether, /* #3 Treasure 10% */
        3000000000 ether, /* #4 Team Reserved 15% */
        1000000000 ether, /* #5 Advisors 5% */
        3000000000 ether  /* #6 Investors 15% */
    ];

    uint256[] public releaseIntervals = [
          5479452 ether, /* #0 Social Mining Daily Release | Halve every 2 years */
           684931 ether, /* #1 Builder Incentives Daily Release | Halve every 2 years */
                0 ether, /* #2 Marketing Expense | No lock period */
                0 ether, /* #3 Treasure | No lock period */
         83333333 ether, /* #4 Team Reserved Monthly Release | 36-Months Linear Release */
         27777777 ether, /* #5 Advisors Monthly Release | 36-Months Linear Release */
        125000000 ether  /* #6 Investors Monthly Release | 24-Months Linear Release */
    ];

    uint256 public timeIntervals = 1 days; /* Release Intervals for Social Mining & Builder Incentives */

    function setTimeIntervals (uint256 newTimeIntervals) public onlyOwner {
        uint256 ratio = (newTimeIntervals * 1 ether) / timeIntervals;
        releaseIntervals[0] = releaseIntervals[0] * ratio / 1 ether;
        releaseIntervals[1] = releaseIntervals[1] * ratio / 1 ether;
        timeIntervals = newTimeIntervals;
    }

    uint256[] public recentMinted = [
        1693526400, /* #0 Social Mining Starts 2023/9/1 00:00 UTC */
        1693526400, /* #1 Builder Incentives Starts 2023/9/1 00:00 UTC */
                 0, /* #2 Marketing Expense */
                 0, /* #3 Treasure */
        1693526400, /* #4 Team Reserved Starts 2023/9/1 00:00 UTC */
        1693526400, /* #5 Advisors Starts 2023/9/1 00:00 UTC */
        1693526400  /* #6 Investors Starts 2023/9/1 00:00 UTC */
    ];

    uint256[] public alreadyMinted = [0, 0, 0, 0, 0, 0, 0];

    function Mint (uint256 batch, uint256 amount) public onlyOwner {
        require(recentMinted[batch] < block.timestamp, "$MetaX: Please wait for the next release.");
        require(alreadyMinted[batch] + releaseIntervals[batch] <= Allocation[batch], "$MetaX: All the tokens have been allocated.");
        uint256 _amount = releaseIntervals[batch];
        if (batch < 2) {
            recentMinted[batch] += timeIntervals;
        } else if (batch > 3) {
            recentMinted[batch] += 30 days;
        } else {
            require(amount + alreadyMinted[batch] <= Allocation[batch], "$MetaX: All the tokens have been allocated.");
            _amount = amount;
        }
        _mint(Vaults[batch], _amount);
        alreadyMinted[batch] += _amount;
        emit mintRecord(batch, _amount, block.timestamp);
    }

    event mintRecord (uint256 batch, uint256 amount, uint256 time);

    /* Halve every 2 years */
    uint256 public T0;

    function Halve () public onlyOwner {
        require(block.timestamp > T0 + 730 days, "$MetaX: Please wait till the next halving.");
        releaseIntervals[0] /= 2;
        releaseIntervals[1] /= 2;
        T0 += 730 days;
    }

    /* Early Bird */
    bool public alreadyEarlyBird;

    function Mint_EarlyBird (address earlyBirdUser_addr, uint256 earlyBirdUser, address earlyBirdBuilder_addr, uint256 earlyBirdBuilder) public onlyOwner {
        require(!alreadyEarlyBird, "$MetaX: Early Bird Tokens have already been allocated");
        alreadyMinted[0] += earlyBirdUser;
        _mint(earlyBirdUser_addr, earlyBirdUser);
        alreadyMinted[1] += earlyBirdBuilder;
        _mint(earlyBirdBuilder_addr, earlyBirdBuilder);
        alreadyEarlyBird = true;
    }

/** Burn **/
    uint256 public numberBurnt;

    function Burn (address sender, uint256 amount) external {
        require(balanceOf(sender) >= amount, "$MetaX: You don't have enough amount of $MetaX.");
        _burn(sender, amount);
        numberBurnt += amount;
        emit burnRecord(sender, amount, block.timestamp);
    }

    event burnRecord(address smartContract, uint256 amount, uint256 time);
}
