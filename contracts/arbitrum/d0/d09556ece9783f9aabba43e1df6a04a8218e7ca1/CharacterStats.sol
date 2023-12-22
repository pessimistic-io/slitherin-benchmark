// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./SafeCast.sol";
import "./IFarmlandCollectible.sol";
import "./CharacterManager.sol";

contract CharacterStats is CharacterManager {
    using SafeCast for uint256;

// STATE VARIABLES
   
    /// @dev Store the mapping for underlying characters to their stats
    mapping(bytes32 => uint16[]) public stats;
    
    /// @dev Stores the total number of stats boosted by tokenID
    mapping(uint256 => uint16) public getStatBoosted;

    /// @dev Stores the additional stats available to boost for each additional level
    uint16 public statsPerLevel = 3;

// EVENTS

    event StatIncreased(address indexed account, uint256 tokenID, uint256 amount, uint256 statIndex);
    event StatDecreased(address indexed account, uint256 tokenID, uint256 amount, uint256 statIndex);

// EXTERNAL FUNCTIONS

    /// @dev Increases a stat
    /// @param tokenID ID of the token
    /// @param amount to increase
    /// @param statIndex index of stat
    function _increaseStat(uint256 tokenID, uint256 amount, uint256 statIndex)
        internal
    {
        // Get the underlying token hash
        bytes32 wrappedTokenHash = wrappedTokenHashByID[tokenID];
        // Get current stat
        uint16 currentStat = stats[wrappedTokenHash][statIndex];
        // Set standard max stat
        uint16 maxStat = 99;
        if (statIndex == 5) {
            // Health has a different calculation for max stat
            maxStat = getMaxHealth(tokenID).toUint16();
        } else if (statIndex == 6) {
            // Morale has a different calculation for max stat
            maxStat = getMaxMorale(tokenID).toUint16();
        } else if (statIndex > 6) {
            // Experience has a higher max stat
            maxStat = 10000;
        }
        require(currentStat != maxStat, "Stat already at maximum");
        // Check to see if we'll go above the max stat value
        if (currentStat + amount.toUint16() < maxStat + 1) {
            // Increase stat
            stats[wrappedTokenHash][statIndex] += amount.toUint16();
        } else {
            // Set to max for the stat
            stats[wrappedTokenHash][statIndex] = maxStat;
        }
        // Write an event to the chain
        emit StatIncreased(_msgSender(), tokenID, amount, statIndex);
    }

    /// @dev Decreases a stat
    /// @param tokenID ID of the token
    /// @param amount to increase
    /// @param statIndex index of stat
    function _decreaseStat(uint256 tokenID, uint256 amount, uint256 statIndex)
        internal
    {
        // Get the underlying token hash
        bytes32 wrappedTokenHash = wrappedTokenHashByID[tokenID];
        // Get current stat
        uint16 currentStat = stats[wrappedTokenHash][statIndex];
        // Check to see if we'll go below the minimum stat of 1
        if (currentStat > amount.toUint16()) {
            // Decrease stat
            stats[wrappedTokenHash][statIndex] -= amount.toUint16();
        } else {
            // Otherwise set to minimum of 1
            stats[wrappedTokenHash][statIndex] = 1;
        }
        // Write an event to the chain
        emit StatDecreased(_msgSender(), tokenID, amount, statIndex);
    }

    /// @dev Set characters stat to an arbitrary amount
    /// @dev if amount = stat then there's no change
    /// @param tokenID Characters ID
    /// @param amount to add
    function _setStatTo(uint256 tokenID, uint256 amount, uint256 statIndex)
        internal
    {
        // Get the underlying token hash
        bytes32 wrappedTokenHash = wrappedTokenHashByID[tokenID];
        // Get current stat
        uint16 currentStat = stats[wrappedTokenHash][statIndex];
        if (amount.toUint16() > currentStat) {
            _increaseStat(tokenID, amount.toUint16() - currentStat, statIndex);
        } else {
            _decreaseStat(tokenID, currentStat - amount, statIndex);
        }
    }

    /// @dev Boost stats based on level, enables character progression
    /// @param tokenID Characters ID
    /// @param amount amount to increase stat
    /// @param statIndex which stat to increase
    function _boostStat(uint256 tokenID, uint256 amount, uint256 statIndex)
        internal
    {
        // Ensure that only static stats can be increased
        require(statIndex < 5, "Invalid Stat");
        // Ensure that the max stat boost won't be exceeded
        require(amount <= getStatBoostAvailable(tokenID), "This will exceed the available boosts for this character");
        // Increase the state variable tracking the boosts
        getStatBoosted[tokenID] += amount.toUint16();
        // Increase requested Stat
        _increaseStat(tokenID, amount ,statIndex);
    }

// INTERNAL FUNCTIONS

    /// @dev Import or generate character stats
    /// @param collectionAddress the address of the collection
    /// @param wrappedTokenID the id of the NFT to release
    function _storeStats(address collectionAddress, uint256 wrappedTokenID)
        internal
        isRegistered(collectionAddress)
    {
        uint256 stamina; uint256 strength; uint256 speed; uint256 courage; uint256 intelligence; uint256 health; uint256 morale;
        // Calculate the  underlying token hash
        bytes32 wrappedTokenHash = hashWrappedToken(collectionAddress, wrappedTokenID);
        // Ensure the stats haven't previously been generated
        require(stats[wrappedTokenHash].length == 0, "Traits can be created once");
        // If collection is native
        if (characterCollections[collectionAddress].native) {
            // Get Native Character stats
            (, stamina, strength, speed, courage, intelligence) = IFarmlandCollectible(collectionAddress).collectibleTraits(wrappedTokenID);
        } else  {
            // Otherwise generate some random stats
            uint256 range = characterCollections[collectionAddress].range;
            uint256 offset = characterCollections[collectionAddress].offset;
            // Define array to store random numbers
            uint256[] memory randomNumbers = new uint256[](5);
            randomNumbers = _getRandomNumbers(5, wrappedTokenID);
            // Set stat values
            stamina = (randomNumbers[0] % range) + offset;
            strength = (randomNumbers[1] % range) + offset;
            speed = (randomNumbers[2] % range) + offset;
            courage = (randomNumbers[3] % range) + offset;
            intelligence = (randomNumbers[4] % range) + offset;
        }
        // Calculate health
        health = (strength + stamina) / 2;
        // Give bonus for a Tank or Warrior
        if (strength > 95 || stamina > 95)
        {
            health += health / 2;
        }
        // Calculate morale
        morale = (courage + intelligence) / 2 ;
        // Give bonus for a Genius or Hero
        if (courage > 95 || intelligence > 95)
        {
            morale += morale / 2;
        }
        // Assign the stats (experience & level start at 0)
        stats[wrappedTokenHash] = [
            stamina.toUint16(),       // 0
            strength.toUint16(),      // 1
            speed.toUint16(),         // 2
            courage.toUint16(),       // 3
            intelligence.toUint16(),  // 4
            health.toUint16(),        // 5
            morale.toUint16(),        // 6
            0];                       // 7 - experience
    }

    /// @dev Returns an array of Random Numbers
    /// @param n number of random numbers to generate
    /// @param salt a number that adds to randomness
    function _getRandomNumbers(uint256 n, uint256 salt)
        internal
        view
        returns (uint256[] memory randomNumbers)
    {
        randomNumbers = new uint256[](n);
        for (uint256 i = 0; i < n;) {
            randomNumbers[i] = uint256(keccak256(abi.encodePacked(block.timestamp, salt, i)));
            unchecked { i++; }
        }
    }

// ADMIN FUNCTIONS
    
    /// @dev Update the base stats per level
    function updateStatsPerLevel(uint256 newStatsPerLevel)
        external
        onlyOwner
    {
        statsPerLevel = newStatsPerLevel.toUint16();
    }

// VIEW FUNCTIONS

    /// @dev Returns the wrapped characters extended stats
    /// @param tokenID ID of the token
    function getStats(uint256 tokenID)
        public
        view
        returns (
            uint256 stamina, uint256 strength, uint256 speed, uint256 courage, uint256 intelligence, uint256 health, uint256 morale, uint256 experience, uint256 level
        )
    {
        // Get the underlying token hash
        bytes32 wrappedTokenHash = wrappedTokenHashByID[tokenID];
        uint256 total = stats[wrappedTokenHash].length;
        if (total > 7) {
            stamina = stats[wrappedTokenHash][0];
            strength = stats[wrappedTokenHash][1];
            speed = stats[wrappedTokenHash][2];
            courage = stats[wrappedTokenHash][3];
            intelligence = stats[wrappedTokenHash][4];
            health = stats[wrappedTokenHash][5];
            morale = stats[wrappedTokenHash][6];
            experience = stats[wrappedTokenHash][7];
            level = sqrt(experience);
        } else {
            return (0,0,0,0,0,0,0,0,0);
        }
    }  

    /// @dev Returns the wrapped characters level
    /// @param tokenID ID of the token
    function getLevel(uint256 tokenID)
        public
        view
        returns (
            uint256 level
        )
    {
        // Get the underlying token hash
        bytes32 wrappedTokenHash = wrappedTokenHashByID[tokenID];
        // Level is the square root of Experience
        return sqrt(stats[wrappedTokenHash][7]);
    }  
    
    /// @dev Returns the square root of a number
    /// @dev https://github.com/Uniswap/uniswap-v2-core/blob/4dd59067c76dea4a0e8e4bfdda41877a6b16dedc/contracts/libraries/Math.sol#L11-L22
    function sqrt(uint256 y) 
        internal
        pure
        returns (
            uint256 z
        )
    {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    /// @dev Returns a characters default max health
    /// @param tokenID Characters ID
    function getMaxHealth(uint256 tokenID)
        public
        view
        returns (
            uint256 health
        )
    {
        // Retrieve stats
        (uint256 stamina, uint256 strength,,,,,,,) = getStats(tokenID);
        // Calculate the characters health
        health = (strength + stamina) / 2;
        // Bonus for Tank or Warrior
        if (strength > 95 || stamina > 95)
        {
            health += health / 2;
        }
    }

    /// @dev Return a default max morale .. a combination of courage & intelligence
    /// @param tokenID Characters ID
    function getMaxMorale(uint256 tokenID)
        public
        view
        returns (
            uint256 morale
        )
    {
        // Retrieve stats
        (,,,uint256 courage, uint256 intelligence,,,,) = getStats(tokenID);
        // Set Morale
        morale = (courage + intelligence) / 2 ;
        // Bonus for Genius or Hero
        if (courage > 95 || intelligence > 95)
        {
            morale += morale / 2;
        }
    }

    /// @dev Return the stat boost available for a character
    /// @param tokenID Characters ID
    function getStatBoostAvailable(uint256 tokenID)
        public
        view
        returns (uint256 statBoost)
    {
        return (getLevel(tokenID) * statsPerLevel) - getStatBoosted[tokenID];
    }

}

