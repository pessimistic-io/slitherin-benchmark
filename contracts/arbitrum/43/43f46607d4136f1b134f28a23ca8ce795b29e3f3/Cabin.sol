// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "./Ownable.sol";
import "./IERC20.sol";


contract CABIN is Ownable {


    address public sheppard; //this is the address of who made the LP
    address public herd; //this is the LP token
    address public kindling; //this is the donation token
    uint256 public pyre; //this is the amount of donation required
    uint256 public woodpile; //this is the amount of donation already given
    uint256 public water; //this is the cooldown start time for rescuing the LP tokens

    bool public collectingWater; //this starts the cooldown on retrieveing the LPs
    bool public built; //used for init
    uint256 public immutable ONE_WEEK = 604800; //this is the delay on retrieving the LPs

    event cabinBurntDown(address _arsonist);
    event sheppardSavingCabin(uint256 _timestamp);
    event sheppardSavedCabin();
    event addedToWoodPile(uint256 _woodpile);

    /// @notice this function is used to initialize the cabin and set the params.
    function buildTheCabin(address _herd, address _kindling, uint256 _pyre, address _sheppard) public onlyOwner {
        require(!built, 'the cabin is immutable');
        herd = _herd;
        kindling = _kindling;
        pyre = _pyre;
        sheppard = _sheppard;
        built = true;
    }

    /// @notice this function is used by the LP owner to deposit the LP inside
    function sheppardGoHome(uint256 _amount) public onlyOwner {
        IERC20(herd).transferFrom(msg.sender, address(this), _amount);
    }
    /// @notice this function is used to check the balance of LP tokens in this contract
    function cabinBalance() public view returns(uint _cabinBal) {
        return IERC20(herd).balanceOf(address(this));
    }
    /// @notice this function is used to donate some WETH to the LP depositor, There are NO refunds.
    function addToWoodPile(uint256 _logs) public {
        require (IERC20(herd).balanceOf(address(this)) > 0, 'cabin is already burnt down');
        IERC20(kindling).transferFrom(msg.sender, sheppard, _logs);
        woodpile = woodpile + _logs;

        emit addedToWoodPile(woodpile);
    }
    /// @notice this function is used to send the LPs in the contract to the dead addres
    /// requires that enough WETH has been donated with addToWoodPile
    function burnTheCabin() public {
        require (woodpile >= pyre, 'there arent enough logs yet');
        uint256 herdSize = cabinBalance();
        IERC20(herd).transfer(0x000000000000000000000000000000000000dEaD, herdSize);

        emit cabinBurntDown(msg.sender);
    }
    /// @notice this function starts the cooldown period (1 week) for owner to retrieve LPs
    function collectWater() public onlyOwner {
        water = block.timestamp;
        collectingWater = true;

        emit sheppardSavingCabin(block.timestamp);
    }
    /// @notice after one week has passed, the owner can call this to retrieve the LP tokens. 
    function saveTheCabin() public onlyOwner {
        require (water + ONE_WEEK < block.timestamp, 'sheppard, you dont have enough water');
        require (collectingWater == true, 'sheppard, you didnt even start collecting water');
        uint256 herdSize = cabinBalance();
        IERC20(herd).transfer(sheppard, herdSize);

        emit sheppardSavedCabin();
    }


}
