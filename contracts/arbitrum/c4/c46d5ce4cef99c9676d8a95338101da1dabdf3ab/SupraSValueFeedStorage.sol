// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./ISupraSValueFeedVerifier.sol";
import {Ownable2StepUpgradeable} from "./Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "./UUPSUpgradeable.sol";

/// @title Supra Oracle Value Feed Storage Contract
/// @author Supra developer
/// @notice This contract is used for to storing the exchange rate of trading pairs
/// @dev All function calls are currently implemented without side effects
contract SupraSValueFeedStorage is Ownable2StepUpgradeable,UUPSUpgradeable {


    /// @dev To extract the ROUND data of a pair ID on that particular location of the word (32 byte).
    uint256 constant private ROUND=0xffffffffffffffff000000000000000000000000000000000000000000000000;
    /// @dev To extract the DECIMAL data of a pair ID on that particular location of the word (32 byte).
    uint256 constant private DECIMAL=0x0000000000000000ff0000000000000000000000000000000000000000000000;
    /// @dev To extract the TIMESTAMP data of a pair ID on that particular location of the word (32 byte).
    uint256 constant private TIMESTAMP=0x000000000000000000ffffffffffffffff000000000000000000000000000000;
    /// @dev To extract the PRICE data of a pair ID on that particular location of the word (32 byte).
    uint256 constant private PRICE=0x0000000000000000000000000000000000ffffffffffffffffffffffff000000;
    /// @dev To extract the HCC data of a pair ID on that particular location of the word (32 byte).
    uint256 constant private HCC=0x0000000000000000000000000000000000000000000000000000000000ff0000;
    /// @dev Keeping the decimal for the derived prices as 18.
    uint256 constant private MAX_DECIMAL = 18;


    /// @notice Structure of the Unpacked data that does not need HCC validation check data
    struct dataWithoutHcc {
        uint256 round;
        uint256 decimals;
        uint256 time;
        uint256 price;

    }

    /// @notice Structure to Provide the derived prices data
    struct derivedData{
        int256 roundDifference;
        int256 timeDifference;
        uint256 derivedPrice;
        uint256 decimals;
    }

    /// @notice Structure to store the Derived Pairs
    struct derivedPair {
        uint256 basePairId;
        uint256 quotePairId;
        uint256 operation;
    }


    /// @notice Structure of the Unpacked data that does need HCC validation check data
    struct dataWithHcc {
        uint256 round;
        uint256 decimals;
        uint256 time;
        uint256 price;
        uint256 historyConsistent;
    }

    /// @notice It is address of Verifier contract of SupraOracle
    /// @dev It stores contract address of Verifier contract
    address public supraSValueFeedVerifier;
    /// @dev Storing the packed data of a particular pairID 
    mapping(uint256 => bytes32) supraStorage;
    /// @notice Storing the derived pair info data
    mapping(uint256 => derivedPair) public derivedPairs;


    error InvalidVerifier();
    error UnauthorisedAccess(address _actualAddr, address _ownerAddr);
    error PairIdIsAbsentForHCC();
    error PairIdsAreAbsentForHCC();
    error DerivedPairNotAvailable(uint256 pairId);
    error ArrayLengthMismatched();
    error InvalidDerivedPair();

    modifier onlySupraVerifier() {
        if (msg.sender != supraSValueFeedVerifier)
            revert UnauthorisedAccess(msg.sender, supraSValueFeedVerifier);
        _;
    }

    event SupraSValueVerifierUpdated(address _updatedVerifierAddress);


    /// @notice This function will work similar to Constructor as we cannot use constructor while using proxy
    /// @dev Initialize the respective variables once and behaves similar to constructor
    function initialize() public initializer {
        Ownable2StepUpgradeable.__Ownable2Step_init();
    }



    /// @notice Helper function for upgradability
    /// @dev While upgrading using UUPS proxy interface, when we call upgradeTo(address) function
    /// @dev we need to check that only owner can upgrade
    /// @param newImplementation address of the new implementation contract
    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyOwner {}


    /// @notice This function will help to find the prices of the derived pairs
    /// @dev Derived pairs are the one whose price info is calculated using two compatible pairs using either multiplication or division. 
    /// @param _derivedPairId the derived pair id
    /// @return derivedData the structured derived price data 
    function getDerivedSvalue(uint256 _derivedPairId) external view returns (derivedData memory) {
        derivedPair memory _derivedPair = derivedPairs[_derivedPairId];
        if(_derivedPair.basePairId==_derivedPair.quotePairId) revert DerivedPairNotAvailable(_derivedPairId);
        (uint256 _round1,uint256 _decimal1,uint256 _timestamp1,uint256 _price1,)=_unPackData(uint256(supraStorage[_derivedPair.basePairId]));
        (uint256 _round2,uint256 _decimal2,uint256 _timestamp2,uint256 _price2,)=_unPackData(uint256(supraStorage[_derivedPair.quotePairId]));
        uint256 derivedPrice;
        //0->Multiplication 1->Division
        if(_derivedPair.operation==0){
            if((_decimal1+_decimal2)>MAX_DECIMAL){
            derivedPrice = (_price1*_price2)/(10**((_decimal1+_decimal2)-MAX_DECIMAL));
            }
            else{
            derivedPrice = (_price1*_price2)*10**(MAX_DECIMAL-(_decimal1+_decimal2));
            }
        }
        else{
            derivedPrice = (_scalePrice(_price1,_decimal1)*10**MAX_DECIMAL)/_scalePrice(_price2,_decimal2);
        }
        return derivedData(int256(int256(_round1)-int256(_round2)),int256(int256(_timestamp1)-int256(_timestamp2)),derivedPrice,MAX_DECIMAL);
    }

    /// @notice Function to add derive pair ids
    /// @dev The derived pairs are compatible and the details like derived pair id is mapped with native pair ids and operation to perform on them
    /// @param _derivedPairIds list of derived pair ids to be added
    /// @param _derivedPairs list of derived pair info to be mapped with derive pair ids

    function addDerivedPairs(uint256[] calldata _derivedPairIds,derivedPair[] calldata _derivedPairs) external onlyOwner {
        if(_derivedPairIds.length!=_derivedPairs.length){
            revert ArrayLengthMismatched();
        }
        for (uint256 i=0;i<_derivedPairIds.length;++i){
            // Condition 1 :: We are ensuring that we are not going to re-initialize a Derived Pair ID.
            // Condition 2 :: We are making sure that the base and the qoute pair Id of a derived pair are different.
            if((derivedPairs[_derivedPairIds[i]].basePairId != derivedPairs[_derivedPairIds[i]].quotePairId) || (_derivedPairs[i].basePairId == _derivedPairs[i].quotePairId))
            {
                revert InvalidDerivedPair();
            }
            derivedPairs[_derivedPairIds[i]]=_derivedPairs[i];
        }
            
    }

    /// @notice Function to remove derive pair ids
    /// @dev The derived pairs are compatible and the details like derived pair id is mapped with native pair ids and operation to perform on them
    /// @param _derivedPairIds list of derived pair ids to be added

    function removeDerivedPairs(uint256[] calldata _derivedPairIds) external onlyOwner {
        for (uint256 i=0;i<_derivedPairIds.length;++i){
            delete derivedPairs[_derivedPairIds[i]];
        }
            
    }


    /// @notice Get the all the data for a single trading pair.
    /// @dev Checks whether that pair ID is included in the HCC list or not 
    /// @dev It takes the data of a pair ID from supraStorage variable
    /// @dev Unpacks them and returns in a structure format  
    /// @param _pairIndex The index of the trading pair.
    /// @return The structured data with HCC 

    function getSvalueWithHCC(uint256 _pairIndex)
        external
        view
        returns (dataWithHcc memory)
    {
        if(!ISupraSValueFeedVerifier(supraSValueFeedVerifier).isPairAlreadyAddedForHCC(_pairIndex)){
            revert PairIdIsAbsentForHCC();
        }
        (uint256 _round,uint256 _decimal,uint256 _timestamp,uint256 _price,uint256 _hcc)=_unPackData(uint256(supraStorage[_pairIndex]));
        return dataWithHcc(_round,_decimal,_timestamp,_price,_hcc);
    }



    /// @notice Get the all the data for Multiple trading pairs.
    /// @dev Checks whether that pair IDs are included in the HCC list or not 
    /// @dev It takes the data of a multiple pair IDs from supraStorage variable
    /// @dev Unpacks them and returns in a array of structure format  
    /// @param _pairIndexes The list of indexes of trading pairs.
    /// @return The array of structured data with HCC 



    function getSvaluesWithHCC(uint256[] calldata _pairIndexes)
        external
        view
        returns (dataWithHcc[] memory)
    {
        if(!ISupraSValueFeedVerifier(supraSValueFeedVerifier).isPairAlreadyAddedForHCC(_pairIndexes)){
            revert PairIdsAreAbsentForHCC();
        }
        dataWithHcc[] memory storedata = new dataWithHcc[](_pairIndexes.length);
        for (uint256 loop = 0; loop < _pairIndexes.length; ++loop) {
            (uint256 _round,uint256 _decimal,uint256 _timestamp,uint256 _price,uint256 _hcc)=_unPackData(uint256(supraStorage[_pairIndexes[loop]]));
            storedata[loop] = dataWithHcc(_round,_decimal,_timestamp,_price,_hcc);
        }
        return (storedata);
    }

    /// @notice Get the all the data for a single trading pair.
    /// @dev It takes the data of a pair ID from supraStorage variable
    /// @dev Unpacks them and returns in a structure format  
    /// @param _pairIndex The index of the trading pair.
    /// @return The structured data without HCC 
   

    function getSvalue(uint256 _pairIndex)
        external
        view
        returns (dataWithoutHcc memory)
    {
        (uint256 _round,uint256 _decimal,uint256 _timestamp,uint256 _price,)=_unPackData(uint256(supraStorage[_pairIndex]));
        return dataWithoutHcc(_round,_decimal,_timestamp,_price);
    }



    /// @notice Get the all the data for Multiple trading pairs.
    /// @dev It takes the data of a multiple pair IDs from supraStorage variable
    /// @dev Unpacks them and returns in a array of structure format  
    /// @param _pairIndexes The list of indexes of trading pairs.
    /// @return The array of structured data without HCC 

    function getSvalues(uint256[] memory _pairIndexes)
        external
        view
        returns (dataWithoutHcc[] memory)
    {
        dataWithoutHcc[] memory storedata = new dataWithoutHcc[](_pairIndexes.length);
        for (uint256 loop = 0; loop < _pairIndexes.length; ++loop) {
            (uint256 _round,uint256 _decimal,uint256 _timestamp,uint256 _price,)=_unPackData(uint256(supraStorage[_pairIndexes[loop]]));
            storedata[loop] = dataWithoutHcc(_round,_decimal,_timestamp,_price);
        }
        return (storedata);
    }




    /// @notice Get the exchange rate value and availability status for a single trading pair.
    /// @param _pairIndex The index of the trading pair.
    /// @return The exchange rate value and a flag indicating if the value is available or not.
    function getSvalue(uint64 _pairIndex)
        external
        view
        returns (bytes32, bool)
    {
        bool flag;
        if (supraStorage[_pairIndex] == bytes32(0)) {
            flag = true;
        }
        return (supraStorage[_pairIndex], flag);
    }

    /// @notice Get the exchange rate values and availability statuses for multiple trading pairs.
    /// @param _pairIndexes An array of trading pair indexes.
    /// @return An array of exchange rate values and an array of flags indicating if the values are available or not.
    function getSvalues(uint64[] memory _pairIndexes)
        external
        view
        returns (bytes32[] memory, bool[] memory)
    {
        bytes32[] memory storedata = new bytes32[](_pairIndexes.length);
        bool[] memory flags = new bool[](_pairIndexes.length);
        for (uint256 loop = 0; loop < _pairIndexes.length; ++loop) {
            storedata[loop] = supraStorage[_pairIndexes[loop]];
            if (supraStorage[_pairIndexes[loop]] == bytes32(0)) {
                flags[loop] = true;
            }
        }
        return (storedata, flags);
    }


    /// @notice Update the address of the Supra Oracle Verifier contract.
    /// @param _supraSValueFeedVerifier The new address of the SupraOracle Verifier contract.
    /// @dev Only the owner of this contract can update the verifier address.
    function updateSupraSValueFeedVerifier(address _supraSValueFeedVerifier)
        public
        onlyOwner
    {
        if (_supraSValueFeedVerifier == address(0)) {
            revert InvalidVerifier();
        }
        supraSValueFeedVerifier = _supraSValueFeedVerifier;

        emit SupraSValueVerifierUpdated(_supraSValueFeedVerifier);
    }

    /// @notice Set the exchange rate value for a specific trading pair.
    /// @param _index The index of the trading pair.
    /// @param _bytes The exchange rate value to be set.
    /// @dev This function is restricted to the Supra Oracle Verifier contract.
    ///      It is used to set the exchange rate value for a trading pair.
    function restrictedSetSupraStorage(uint256 _index, bytes32 _bytes)
        external
        onlySupraVerifier
    {
        supraStorage[_index] = _bytes;
    }

   /// @notice It helps to find the last timestamp on which the data of a paidId is updated.
    function getTimestamp(uint256 _tradingPair)
        external
        view
        returns (uint256)
    {
        return (uint256(supraStorage[_tradingPair]) & TIMESTAMP)>>120;
    }




    /// @notice It helps to Unpack one single word (32 bytes) into many data points 
    /// @dev This function will take one word data in uint256 format, 
    /// @dev Will do unary AND with the particular constants defined 
    /// @dev Will shift the value to the lower bit.
    /// @param data Packed data of a pairID
    /// @return Tuple of uint256 representing round,decimal,timestamp,price,hcc
 
    function _unPackData(
        uint256 data
    ) internal pure returns (uint256,uint256,uint256,uint256,uint256) {
      
        return (uint256(data & ROUND)>>192,uint256(data & DECIMAL)>>184,uint256(data & TIMESTAMP)>>120,uint256(data & PRICE)>>24,uint256(data & HCC)>>16);
        
    }


    /// @notice Helps to scale the price of a pair id to 18 decimal places
    /// @dev checks if the price is in MAX_DECIMAL decimal or not . If not then will convert them to MAX_DECIMAL
    /// @param price the price of the pair ID
    /// @param decimal number of decimals that the pair info supports
    /// @return the scaled prices of the pair

    function _scalePrice(uint256 price,uint256 decimal) internal pure returns(uint256) {
        if (decimal==MAX_DECIMAL) return price;
        else return price*10**(MAX_DECIMAL-decimal);        
    }
}


