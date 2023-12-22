//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./ERC1155BurnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

import "./ISmolRacing.sol";
import "./SmolRacingAdmin.sol";

contract SmolRacing is Initializable, ISmolRacing, ReentrancyGuardUpgradeable, SmolRacingAdmin {

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    // -------------------------------------------------------------
    //                         Initializer
    // -------------------------------------------------------------

    function initialize() external initializer {
        SmolRacingAdmin.__SmolRacingAdmin_init();
    }

    // -------------------------------------------------------------
    //                      External functions
    // -------------------------------------------------------------

    function stakeVehicles(
        SmolCar[] calldata _cars,
        Swolercycle[] calldata _cycles)
    external
    nonReentrant
    contractsAreSet
    whenNotPaused
    {
        require(endEmissionTime == 0 || endEmissionTime > block.timestamp, "Cannot stake");
        require(_cars.length > 0 || _cycles.length > 0, "no tokens given");
        for(uint256 i = 0; i < _cars.length; i++) {
            SmolCar calldata car = _cars[i];
            require(car.numDrivers > 0, "no car drivers given");
            // validation occurs in _stakeVehicleStart
            _stakeVehicle(smolBrains, address(smolCars), Vehicle({
                driverIds: car.driverIds,
                vehicleId: car.carId,
                numRaces: car.numRaces,
                numDrivers: car.numDrivers,
                boostTreasureIds: car.boostTreasureIds,
                boostTreasureQuantities: car.boostTreasureQuantities
            }));
        }
        for(uint256 i = 0; i < _cycles.length; i++) {
            Swolercycle calldata cycle = _cycles[i];
            require(cycle.numDrivers > 0, "no cycle drivers given");
            // validation occurs in _stakeVehicleStart
            uint64[4] memory drivers;
            drivers[0] = cycle.driverIds[0];
            drivers[1] = cycle.driverIds[1];
            _stakeVehicle(smolBodies, address(swolercycles), Vehicle({
                driverIds: drivers,
                vehicleId: cycle.cycleId,
                numRaces: cycle.numRaces,
                numDrivers: cycle.numDrivers,
                boostTreasureIds: cycle.boostTreasureIds,
                boostTreasureQuantities: cycle.boostTreasureQuantities
            }));
        }
    }

    function unstakeVehicles(
        uint256[] calldata _carTokens,
        uint256[] calldata _cycleTokens)
    external
    nonReentrant
    contractsAreSet
    whenNotPaused
    {
        require(_carTokens.length > 0 || _cycleTokens.length > 0, "no tokens given");
        for(uint256 i = 0; i < _carTokens.length; i++) {
            _unstakeVehicle(smolBrains, address(smolCars), _carTokens[i]);
        }
        for(uint256 i = 0; i < _cycleTokens.length; i++) {
            _unstakeVehicle(smolBodies, address(swolercycles), _cycleTokens[i]);
        }
    }

    function restakeVehicles(
        uint256[] calldata _carTokens,
        uint256[] calldata _cycleTokens)
    external
    nonReentrant
    contractsAreSet
    whenNotPaused
    {
        require(endEmissionTime == 0 || endEmissionTime > block.timestamp, "Cannot restake");
        require(_carTokens.length > 0 || _cycleTokens.length > 0, "no tokens given");
        for(uint256 i = 0; i < _carTokens.length; i++) {
           _restakeVehicle(address(smolCars), _carTokens[i]);
        }
        for(uint256 i = 0; i < _cycleTokens.length; i++) {
           _restakeVehicle(address(swolercycles), _cycleTokens[i]);
        }
    }

    function claimRewardsForVehicles(
        uint256[] calldata _carTokens,
        uint256[] calldata _cycleTokens)
    external
    nonReentrant
    contractsAreSet
    whenNotPaused
    {
        require(_carTokens.length > 0 || _cycleTokens.length > 0, "no tokens given");
        for(uint256 i = 0; i < _carTokens.length; i++) {
           _claimRewardsForVehicle(address(smolCars), _carTokens[i]);
        }
        for(uint256 i = 0; i < _cycleTokens.length; i++) {
           _claimRewardsForVehicle(address(swolercycles), _cycleTokens[i]);
        }
    }

    function ownsVehicle(address _collection, address _owner, uint256 _tokenId) external view returns (bool) {
        return userToVehiclesStaked[_collection][_owner].contains(_tokenId);
    }

    function vehiclesOfOwner(address _collection, address _owner) external view returns (uint256[] memory) { 
        return userToVehiclesStaked[_collection][_owner].values();
    }

    // Gassy, do not call from other contracts
    function smolsOfOwner(address _collection, address _owner) external view returns (uint256[] memory) { 
        uint256[] memory vehicles = userToVehiclesStaked[_collection][_owner].values();
        uint256 numDrivers;
        for (uint i = 0; i < vehicles.length; i++) {
            uint256 vehicleId = vehicles[i];
            numDrivers += vehicleIdToVehicleInfo[_collection][vehicleId].numDrivers;
        }

        uint256[] memory retVal = new uint256[](numDrivers);
        for (uint i = 0; i < vehicles.length; i++) {
            Vehicle memory vehicleInfo = vehicleIdToVehicleInfo[_collection][vehicles[i]];
            // numDrivers may be < 4 if the vehicle isn't full of smols
            for (uint j = 0; j < vehicleInfo.numDrivers; j++) {
                uint256 driverCur = vehicleInfo.driverIds[j];
                if(driverCur == 0) {
                    continue;
                }
                retVal[i + j] = driverCur;
            }
        }
        return retVal;
    }

    //Will return 0 if vehicle isnt staked or there are no races to claim
    function numberOfRacesToClaim(address _vehicleAddress, uint256 _tokenId) public view returns(uint256) {
        uint64 curTime = (endEmissionTime == 0 || block.timestamp < endEmissionTime)
            ? uint64(block.timestamp) : uint64(endEmissionTime);

        RacingInfo memory _info = vehicleIdToRacingInfo[_vehicleAddress][_tokenId];

        // Not staked, otherwise this would be the timestamp that the user was staked at
        if(_info.lastClaimed == 0) {
            return 0;
        }

        uint8 maxAvailable = _info.totalRaces - _info.racesCompleted;
        uint256 uncappedPending = (curTime < _info.lastClaimed ? 0
            : curTime - _info.lastClaimed) / timeForReward;

        if(uncappedPending > maxAvailable) {
            return maxAvailable;
        }
        return uncappedPending;
    }

    //Will return 0 if vehicle isnt staked or there are no races to claim
    function vehicleOddsBoost(address _vehicleAddress, uint256 _tokenId) public view returns(uint256) {
        return vehicleIdToRacingInfo[_vehicleAddress][_tokenId].boostedOdds;
    }

    //Will return 0 if vehicle isnt staked or there are no races to claim
    function vehicleRacingInfo(address _vehicleAddress, uint256 _tokenId) external view returns(RacingInfo memory) {
        return vehicleIdToRacingInfo[_vehicleAddress][_tokenId];
    }

    // -------------------------------------------------------------
    //                       Private functions
    // -------------------------------------------------------------

    function _stakeVehicle(IERC721 _smol, address _vehicleAddress, Vehicle memory _vehicle) private {
        require(_vehicle.driverIds.length > 0, "No drivers");

        userToVehiclesStaked[_vehicleAddress][msg.sender].add(_vehicle.vehicleId);
        vehicleIdToVehicleInfo[_vehicleAddress][_vehicle.vehicleId] = _vehicle;
        uint64 curTime = uint64(block.timestamp);
        vehicleIdToRacingInfo[_vehicleAddress][_vehicle.vehicleId] = RacingInfo({
            racingStartTime: curTime,
            totalRaces: _vehicle.numRaces,
            racesCompleted: 0,
            lastClaimed: curTime,
            boostedOdds: _calculateBoostOdds(_vehicleAddress, _vehicle)
        });

        uint256 numDrivers;
        for (uint i = 0; i < _vehicle.driverIds.length; i++) {
            // Doesn't have to have a full vehicle
            if(_vehicle.driverIds[i] == 0) {
                break;
            }
            numDrivers += 1;
            // will revert if does not own
            _smol.safeTransferFrom(msg.sender, address(this), _vehicle.driverIds[i]);
            emit SmolStaked(msg.sender, address(_smol), _vehicle.driverIds[i], curTime);
        }

        // Verify that the given number of drivers match the array.
        // This info is needed to not have to loop for every claim
        require(numDrivers == _vehicle.numDrivers, "incorrect number of drivers given");

        // will revert if does not own
        IERC721(_vehicleAddress).safeTransferFrom(msg.sender, address(this), _vehicle.vehicleId);

        uint256 _requestId = randomizer.requestRandomNumber();
        // always set this, as it will re-set any previous request ids
        //  to get new randoms when staking/unstaking
        tokenIdToRequestId[_vehicleAddress][_vehicle.vehicleId] = _requestId;

        emit StartRacing(
            msg.sender,
            _vehicleAddress,
            _vehicle.vehicleId,
            curTime,
            _vehicle.numRaces,
            _vehicle.driverIds,
            _requestId
        );
    }

    function _restakeVehicle(address _vehicleAddress, uint256 _tokenId) private {
        require(userToVehiclesStaked[_vehicleAddress][msg.sender].contains(_tokenId), "token not staked");

        // store needed state in memory
        Vehicle memory vehicleInfo = vehicleIdToVehicleInfo[_vehicleAddress][_tokenId];
        RacingInfo memory racingInfo = vehicleIdToRacingInfo[_vehicleAddress][_tokenId];
        uint256 pendingRaceRewards = numberOfRacesToClaim(_vehicleAddress, _tokenId);

        // Must finish their racing circuit before returning
        require(racingInfo.racesCompleted + pendingRaceRewards >= racingInfo.totalRaces, "not done racing");

        // claim any rewards pending
        if(pendingRaceRewards > 0) {
            _claimRewards(pendingRaceRewards, _vehicleAddress, _tokenId, racingInfo);
        }
        
        uint64 curTime = uint64(block.timestamp);
        
        // remove vehicle boosts when re-racing 
        vehicleIdToVehicleInfo[_vehicleAddress][_tokenId] = Vehicle({
            driverIds: vehicleInfo.driverIds,
            vehicleId: vehicleInfo.vehicleId,
            numRaces: vehicleInfo.numRaces,
            numDrivers: vehicleInfo.numDrivers,
            boostTreasureIds: new uint64[](0),
            boostTreasureQuantities: new uint32[](0)
        });

        vehicleIdToRacingInfo[_vehicleAddress][_tokenId] = RacingInfo({
            racingStartTime: curTime,
            totalRaces: vehicleInfo.numRaces,
            racesCompleted: 0,
            lastClaimed: curTime,
            boostedOdds: _calculateBoostOdds(_vehicleAddress, vehicleIdToVehicleInfo[_vehicleAddress][_tokenId]) // Must pull from storage
        });

        uint256 _requestId = randomizer.requestRandomNumber();
        // always set this, as it will re-set any previous request ids
        //  to get new randoms when staking/unstaking
        tokenIdToRequestId[_vehicleAddress][vehicleInfo.vehicleId] = _requestId;

        emit RestartRacing(
            msg.sender,
            _vehicleAddress,
            vehicleInfo.vehicleId,
            curTime,
            vehicleInfo.numRaces,
            vehicleInfo.driverIds,
            _requestId
        );
    }

    function _unstakeVehicle(IERC721 _smol, address _vehicleAddress, uint256 _tokenId) private {
        require(userToVehiclesStaked[_vehicleAddress][msg.sender].contains(_tokenId), "token not staked");

        // store needed state in memory
        Vehicle memory vehicleInfo = vehicleIdToVehicleInfo[_vehicleAddress][_tokenId];
        RacingInfo memory racingInfo = vehicleIdToRacingInfo[_vehicleAddress][_tokenId];
        uint256 pendingRaceRewards = numberOfRacesToClaim(_vehicleAddress, _tokenId);

        // Must finish their racing circuit before returning
        if(endEmissionTime == 0 || block.timestamp < endEmissionTime) {
            require(racingInfo.racesCompleted + pendingRaceRewards >= racingInfo.totalRaces, "not done racing");
        }
        else {
            // Assume the last race will not be able to be completed
            require(racingInfo.racesCompleted + pendingRaceRewards >= racingInfo.totalRaces - 1, "not done racing");
        }

        // remove state
        delete vehicleIdToVehicleInfo[_vehicleAddress][_tokenId];
        delete vehicleIdToRacingInfo[_vehicleAddress][_tokenId];
        userToVehiclesStaked[_vehicleAddress][msg.sender].remove(_tokenId);

        // claim any rewards pending
        if(pendingRaceRewards > 0) {
            _claimRewards(pendingRaceRewards, _vehicleAddress, _tokenId, racingInfo);
        }

        // unstake all
        uint64 curTime = uint64(block.timestamp);
        for (uint i = 0; i < vehicleInfo.driverIds.length; i++) {
            // Doesn't have to have a full vehicle
            if(vehicleInfo.driverIds[i] == 0) {
                break;
            }
            _smol.safeTransferFrom(address(this), msg.sender, vehicleInfo.driverIds[i]);
            emit SmolUnstaked(msg.sender, address(_smol), vehicleInfo.driverIds[i]);
        }

        IERC721(_vehicleAddress).safeTransferFrom(address(this), msg.sender, vehicleInfo.vehicleId);

        emit StopRacing(
            msg.sender,
            _vehicleAddress,
            vehicleInfo.vehicleId,
            curTime,
            vehicleInfo.numRaces
        );
    }

    function _claimRewardsForVehicle(address _vehicleAddress, uint256 _tokenId) private {
        require(userToVehiclesStaked[_vehicleAddress][msg.sender].contains(_tokenId), "not vehicle owner");

        uint256 count = numberOfRacesToClaim(_vehicleAddress, _tokenId);
        require(count > 0, "nothing to claim");

        RacingInfo memory racingInfo = vehicleIdToRacingInfo[_vehicleAddress][_tokenId];
        racingInfo.lastClaimed += uint64(count * timeForReward);

        _claimRewards(count, _vehicleAddress, _tokenId, racingInfo);
        
        racingInfo.racesCompleted += uint8(count);

        vehicleIdToRacingInfo[_vehicleAddress][_tokenId] = racingInfo;
    }

    function _claimRewards(uint256 numRewards, address _vehicleAddress, uint256 _tokenId, RacingInfo memory _info) private {
        uint256 seed = _getRandomSeedForVehicle(_vehicleAddress, _tokenId);
        for (uint i = 0; i < numRewards; i++) {
            uint256 curRace = _info.racesCompleted + i + 1;
            uint256 random = uint256(keccak256(abi.encode(seed, curRace)));
            _claimReward(_vehicleAddress, _tokenId, _info.boostedOdds, random);
        }
    }

    function _claimReward(address _vehicleAddress, uint256 _tokenId, uint32 _boostedOdds, uint256 _randomNumber) private {
        uint256 _rewardResult = (_randomNumber % ODDS_DENOMINATOR) + _boostedOdds;
        if(_rewardResult >= ODDS_DENOMINATOR) {
            _rewardResult = ODDS_DENOMINATOR - 1; // This is the 0 based max value for modulus
        }

        uint256 _topRange = 0;
        uint256 _claimedRewardId = 0;
        for(uint256 i = 0; i < rewardOptions.length; i++) {
            uint256 _rewardId = rewardOptions[i];
            _topRange += rewardIdToOdds[_rewardId];
            if(_rewardResult < _topRange) {
                // _rewardId of 0 denotes that a reward should not be minted (bad luck roll)
                if(_rewardId != 0) {
                    _claimedRewardId = _rewardId;

                    // Each driver earns a reward
                    racingTrophies.mint(msg.sender, _claimedRewardId, 1);
                }
                break; // always break to avoid walking the array
            }
        }
        if(_claimedRewardId > 0) {
            emit RewardClaimed(msg.sender, _vehicleAddress, _tokenId, _claimedRewardId, 1);
        }
        else {
            emit NoRewardEarned(msg.sender, _vehicleAddress, _tokenId);
        }
    }

    function _calculateBoostOdds(address _vehicleAddress, Vehicle memory _vehicle) private returns (uint32 boostOdds_) {
        // Additional driver boosts
        if(_vehicleAddress == address(smolCars)) {
            boostOdds_ += ((_vehicle.numDrivers - 1) * additionalSmolBrainBoost); 
        }
        else if(_vehicleAddress == address(swolercycles)) {
            if(_vehicle.numDrivers == 2) {
                boostOdds_ += additionalSmolBodyBoost; 
            }
        }

        // Treasure boosts
        uint256 numBoostItems = _vehicle.boostTreasureIds.length;
        require(numBoostItems == _vehicle.boostTreasureQuantities.length, "Number of treasures much match quantities");
        for (uint i = 0; i < numBoostItems; i++) {
            // burn vs burnBatch because we are already looping which batch would also do
            treasures.burn(msg.sender, _vehicle.boostTreasureIds[i], _vehicle.boostTreasureQuantities[i]);
            
            uint32 boostPerItem = smolTreasureIdToOddsBoost[_vehicle.boostTreasureIds[i]];
            boostOdds_ += boostPerItem * _vehicle.boostTreasureQuantities[i];
        }
        if(boostOdds_ > maxOddsBoostAllowed) {
            // Cannot exceed the max amount of boosted odds
            boostOdds_ = maxOddsBoostAllowed;
        }
    }

    function _getRandomSeedForVehicle(address _vehicleAddress, uint256 _tokenId) private view returns (uint256) {
        uint256 _requestId = tokenIdToRequestId[_vehicleAddress][_tokenId];
        // No need to do sanity checks as they already happen inside of the randomizer
        return randomizer.revealRandomNumber(_requestId);
    }

}
