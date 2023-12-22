// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

/*

Transmolgrifier.sol
Written by: mousedev.eth

*/

import "./IERC721.sol";
import "./AccessControlEnumerableV2.sol";
import "./SmolsAddressRegistryConsumer.sol";
import "./ISmolsState.sol";
import "./SmolsLibrary.sol";
import "./ISchool.sol";


contract Transmolgrifier is AccessControlEnumerableV2, SmolsAddressRegistryConsumer {

	struct SmolData {
		Smol smol;
		bool exists;
		uint8 smolInputAmount;
	}

	struct TransmolgrifyRequest {
		uint256 smolRecipeId;
		uint256 smolIdToTransmolgrify;
		uint256[] smolIdsToBurn;
	}

	mapping(uint256 => SmolData) public smolRecipeIdToSmolData;

	uint256 currentSmolRecipeId;

	bool transmolgActive = false;

	event SmolTransmolgrified(uint256 smolIdToTransmolgrify, uint256 smolRecipeId, uint256[] smolIdsToBurn);
	event SmolRecipeDeleted(uint256 smolRecipeId);
	event SmolRecipeAdded(uint256 smolRecipeId, SmolData smolData);
	event SmolRecipeAdjusted(uint256 smolRecipeId, SmolData smolData);


	function transmolgrify(TransmolgrifyRequest[] calldata _transmolgrifyRequests) external {

		require(transmolgActive, "Transmolg isn't currently active!");

		for(uint256 i = 0;i<_transmolgrifyRequests.length;i++){
			TransmolgrifyRequest calldata _transmolgrifyRequest = _transmolgrifyRequests[i]; 

			uint256 _smolRecipeId = _transmolgrifyRequest.smolRecipeId;
			uint256 _smolIdToTransmolgrify = _transmolgrifyRequest.smolIdToTransmolgrify;
			uint256[] calldata _smolIdsToBurn = _transmolgrifyRequest.smolIdsToBurn;

			//Load this recipe tier into storage
			SmolData storage smolData = smolRecipeIdToSmolData[_smolRecipeId];

			//Require they sent the correct amount of smols to correlate with this recipe tier
			require(_smolIdsToBurn.length == smolData.smolInputAmount, "Supplied smols not equal to cost!");

			require(smolData.exists, "Recipe does not exist!");

			smolData.exists = false;

			//Pull the relevant smols addresses from the registry
			address smolsAddress = smolsAddressRegistry.getAddress(SmolAddressEnum.SMOLSADDRESS);
			address smolsStateAddress = smolsAddressRegistry.getAddress(SmolAddressEnum.SMOLSSTATEADDRESS);
			address schoolAddress = smolsAddressRegistry.getAddress(SmolAddressEnum.SCHOOLADDRESS);

			uint128 _iqToGrant = 0;

			//Loop through the array of ids to burn
			for(uint256 j = 0; j < smolData.smolInputAmount; j++){
				require(ISmolsState(smolsStateAddress).getInitialSmol(_smolIdsToBurn[j]).gender == 2, "Not a female burn smol!");

				//Pull the iq of the to-be-burned smol from the school
				uint128 _iqOfSmol = ISchool(schoolAddress).tokenDetails(smolsAddress, 0, _smolIdsToBurn[j]).statAccrued;

				//Remove all the iq of the smol
				ISchool(schoolAddress).removeStatAsAllowedAdjuster(smolsAddress, 0, _smolIdsToBurn[j], _iqOfSmol);

				//Add it to the aggregate amount of iq to grant.
				_iqToGrant += _iqOfSmol;

				//Burn the smol
				IERC721(smolsAddress).transferFrom(msg.sender, 0x000000000000000000000000000000000000dEaD, _smolIdsToBurn[j]);
			}

			//Give the aggregate IQ to the to-be-adjusted smol
			ISchool(schoolAddress).addStatAsAllowedAdjuster(smolsAddress, 0, _smolIdToTransmolgrify, _iqToGrant);
			
			//Require transmol is female
			require(ISmolsState(smolsStateAddress).getInitialSmol(_smolIdToTransmolgrify).gender == 2, "Not a female transmol!");

			//Ensure they own the to-be-adjusted smol
			require(IERC721(smolsAddress).ownerOf(_smolIdToTransmolgrify) == msg.sender, "You don't own the subject smol!");

			//Set the initial smol to the recipe chosen
			ISmolsState(smolsStateAddress).setInitialSmol(_smolIdToTransmolgrify, smolData.smol);
			
			emit SmolTransmolgrified(_smolIdToTransmolgrify, _smolRecipeId, _smolIdsToBurn);
		}

	}

	function setTransmolgActive(bool _transmolgActive) external requiresRole(OWNER_ROLE) {
		transmolgActive = _transmolgActive;
	}

	function deleteSmolRecipes(uint256[] calldata _smolRecipeIds) external requiresRole(OWNER_ROLE) {
		for(uint256 i = 0;  i < _smolRecipeIds.length;i++){
			delete smolRecipeIdToSmolData[_smolRecipeIds[i]];
			
			emit SmolRecipeDeleted(_smolRecipeIds[i]);
		}
	}

	function addSmolRecipes(SmolData[] calldata _smolsData) external requiresRole(OWNER_ROLE) {
		for(uint256 i = 0; i <_smolsData.length; i++){
			//Create this smol recipe ID.
			uint256 thisSmolRecipeId = currentSmolRecipeId + i;

			//Initialize and set the SmolData struct in storage.
			SmolData storage _smolData = smolRecipeIdToSmolData[thisSmolRecipeId];

			_smolData.smol = _smolsData[i].smol;
			_smolData.exists = true;
			_smolData.smolInputAmount = _smolsData[i].smolInputAmount;

			emit SmolRecipeAdded(thisSmolRecipeId, _smolData);
		}

		//Add as many smols as we created to currentSmolRecipeId
		currentSmolRecipeId += _smolsData.length;
	}

	function adjustSmolRecipe(uint256[] calldata _smolRecipeIds, SmolData[] calldata _newSmolsData) external requiresRole(OWNER_ROLE) {
		for(uint256 i = 0; i <_smolRecipeIds.length; i++){
			//Initialize and set the SmolData struct in storage.
			SmolData storage _smolData = smolRecipeIdToSmolData[_smolRecipeIds[i]];

			require(_smolData.exists, "Smol recipe does not exist!");

			_smolData.smol = _newSmolsData[i].smol;
			_smolData.smolInputAmount = _newSmolsData[i].smolInputAmount;

			
			emit SmolRecipeAdjusted(_smolRecipeIds[i], _smolData);
		}
	}

	/*

	View func for frontend

	*/

	struct RecipeStatus {
		bool exists;
		uint256 recipeId;
	}

	function getStatusOfRecipes(uint256[] calldata _recipeIds) external view returns(RecipeStatus[] memory) {
		RecipeStatus[] memory recipeStatusReturn = new RecipeStatus[](_recipeIds.length);

		for(uint256 i =0;i<_recipeIds.length;i++){
			SmolData storage _smolData = smolRecipeIdToSmolData[_recipeIds[i]];

			recipeStatusReturn[i] = RecipeStatus(
				_smolData.exists,
				_recipeIds[i]
			);
		}

		return recipeStatusReturn;
	}
}

