//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";

import "./CorruptionRemovalContracts.sol";
import "./ICustomRemovalHandler.sol";

contract CorruptionRemoval is Initializable, CorruptionRemovalContracts {

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    function initialize() external initializer {
        CorruptionRemovalContracts.__CorruptionRemovalContracts_init();
    }

    function createCorruptionRemovalRecipe(
        uint256 _corruptionRemoved,
        RecipeItemEvent[] calldata _items,
        MalevolentPrismStepEvent[] calldata _malevolentPrismSteps)
    external
    onlyAdminOrOwner
    {
        uint256 _recipeId = recipeIdCur;
        recipeIdCur++;

        recipeIdToInfo[_recipeId].corruptionRemoved = _corruptionRemoved;

        for(uint256 i = 0; i < _items.length; i++) {
            RecipeItemEvent calldata _item = _items[i];

            if(_item.itemEffect == ItemEffect.CUSTOM) {
                require(_item.customHandler != address(0), "Custom handler must be set");
            }

            recipeIdToInfo[_recipeId].items.push(RecipeItem(
                _item.itemAddress,
                _item.itemType,
                _item.itemEffect,
                _item.effectChance,
                0,
                _item.itemId,
                _item.amount,
                0,
                _item.customHandler,
                0,
                _item.customRequirementData,
                0,
                0
            ));
        }

        for(uint256 i = 0; i < _malevolentPrismSteps.length; i++) {
            MalevolentPrismStepEvent calldata _step = _malevolentPrismSteps[i];

            recipeIdToInfo[_recipeId].prismSteps.push(MalevolentPrismStep(
                _step.maxCorruptionAmount,
                _step.chanceOfDropping,
                _step.amount,
                0
            ));
        }

        emit CorruptionRemovalRecipeCreated(
            _recipeId,
            _corruptionRemoved,
            _items,
            _malevolentPrismSteps
        );
    }

    function addRecipeToBuilding(
        address _buildingAddress,
        uint256 _recipeId
    )
    external
    onlyAdminOrOwner
    isValidRecipe(_recipeId)
    {
        require(!buildingAddressToInfo[_buildingAddress].recipeIds.contains(_recipeId), "Already on building");

        buildingAddressToInfo[_buildingAddress].recipeIds.add(_recipeId);

        emit CorruptionRemovalRecipeAdded(_buildingAddress, _recipeId);
    }

    function removeRecipeFromBuilding(
        address _buildingAddress,
        uint256 _recipeId)
    external
    onlyAdminOrOwner
    isValidRecipeForBuilding(_buildingAddress, _recipeId)
    {

        buildingAddressToInfo[_buildingAddress].recipeIds.remove(_recipeId);

        emit CorruptionRemovalRecipeRemoved(_buildingAddress, _recipeId);
    }

    modifier isValidRecipeForBuilding(address _buildingAddress, uint256 _recipeId) {
        require(buildingAddressToInfo[_buildingAddress].recipeIds.contains(_recipeId), "Recipe DNE on building");

        _;
    }

    modifier isValidRecipe(uint256 _recipeId) {
        require(recipeIdToInfo[_recipeId].corruptionRemoved > 0, "Recipe DNE");

        _;
    }

    function startRemovingCorruption(
        StartRemovingCorruptionParams[] calldata _params)
    external
    contractsAreSet
    whenNotPaused
    onlyEOA
    {
        for(uint256 i = 0; i < _params.length; i++) {
            _startRemovingCorruption(_params[i]);
        }
    }

    function _startRemovingCorruption(
        StartRemovingCorruptionParams calldata _params)
    private
    isValidRecipeForBuilding(_params.buildingAddress, _params.recipeId)
    {
        uint128 _requestId = uint128(randomizer.requestRandomNumber());

        // Emit before any item handling
        emit CorruptionRemovalStarted(
            msg.sender,
            _params.buildingAddress,
            _params.recipeId,
            _requestId
        );

        RecipeInfo storage _recipeInfo = recipeIdToInfo[_params.recipeId];
        require(_params.customData.length == _recipeInfo.items.length, "Bad customData length");

        for(uint256 i = 0; i < _recipeInfo.items.length; i++) {
            RecipeItem storage _item = _recipeInfo.items[i];

            if(_item.itemEffect == ItemEffect.CUSTOM) {
                ICustomRemovalHandler(_item.customHandler).removalStarted(msg.sender, _requestId, _item.customRequirementData, _params.customData[i]);
            } else if(_item.effectChance == 0) {
                continue;
            } else if(_item.effectChance == 100000) {
                // To save on gas, do the final effect when it is a 100% chance.
                _performItemEffect(_item, msg.sender);
            } else {
                _moveItems(_item, msg.sender, address(this));
            }
        }

        userToInfo[msg.sender].requestIdToRemoval[_requestId].hasStarted = true;
        userToInfo[msg.sender].requestIdToRemoval[_requestId].recipeId = uint64(_params.recipeId);
        userToInfo[msg.sender].requestIdToRemoval[_requestId].buildingAddress = _params.buildingAddress;
    }

    function endRemovingCorruption(
        uint256[] calldata _requestIds)
    external
    contractsAreSet
    whenNotPaused
    onlyEOA
    {
        for(uint256 i = 0; i < _requestIds.length; i++) {
            _endRemovingCorruption(_requestIds[i]);
        }
    }

    function _endRemovingCorruption(
        uint256 _requestId)
    private
    {
        require(userToInfo[msg.sender].requestIdToRemoval[_requestId].hasStarted, "Invalid request id");
        require(!userToInfo[msg.sender].requestIdToRemoval[_requestId].hasFinished, "Already finished");

        userToInfo[msg.sender].requestIdToRemoval[_requestId].hasFinished = true;

        address _buildingAddress = userToInfo[msg.sender].requestIdToRemoval[_requestId].buildingAddress;
        uint256 _recipeId = userToInfo[msg.sender].requestIdToRemoval[_requestId].recipeId;

        uint256 _randomNumber = randomizer.revealRandomNumber(_requestId);

        RecipeInfo storage _recipeInfo = recipeIdToInfo[_recipeId];
        bool[] memory _effectHit = new bool[](_recipeInfo.items.length);

        for(uint256 i = 0; i < _recipeInfo.items.length; i++) {
            RecipeItem storage _item = _recipeInfo.items[i];

            if(_item.itemEffect == ItemEffect.CUSTOM) {
                ICustomRemovalHandler(_item.customHandler).removalEnded(msg.sender, _requestId, _randomNumber, _item.customRequirementData);
                _randomNumber = uint256(keccak256(abi.encodePacked(_randomNumber, _randomNumber)));
                _effectHit[i] = true;
            } else if(_item.effectChance == 0) {
                // Nothing needed
                continue;
            } else if(_item.effectChance == 100000) {
                // Already performed at the start.
                _effectHit[i] = true;
                continue;
            } else {
                uint256 _result = _randomNumber % 100000;
                _randomNumber = uint256(keccak256(abi.encodePacked(_randomNumber, _randomNumber)));
                if(_result < _item.effectChance) {
                    // Hit
                    _performItemEffect(_item, address(this));
                    _effectHit[i] = true;
                } else {
                    _moveItems(_item, address(this), msg.sender);
                }
            }
        }

        uint256 _corruptionBalance = corruption.balanceOf(_buildingAddress);
        uint256 _prismMinted = _mintPrismIfNeeded(_recipeInfo, _corruptionBalance, _randomNumber);

        uint256 _corruptionToRemove = _recipeInfo.corruptionRemoved;
        if(_corruptionToRemove > _corruptionBalance) {
            _corruptionToRemove = _corruptionBalance;
        }
        corruption.burn(_buildingAddress, _corruptionToRemove);

        emit CorruptionRemovalEnded(
            msg.sender,
            _buildingAddress,
            _requestId,
            _recipeId,
            _recipeInfo.corruptionRemoved,
            _prismMinted,
            _effectHit
        );
    }

    function _mintPrismIfNeeded(
        RecipeInfo storage _recipeInfo,
        uint256 _corruptionBalance,
        uint256 _randomNumber)
    private
    returns(uint256)
    {
        uint256 _result = _randomNumber % 100000;

        for(uint256 i = 0; i < _recipeInfo.prismSteps.length; i++) {
            MalevolentPrismStep storage _step = _recipeInfo.prismSteps[i];

            if(_corruptionBalance < _step.maxCorruptionAmount) {
                // Check if got prism
                if(_result < _step.chanceOfDropping) {
                    consumable.mint(msg.sender, MALEVOLENT_PRISM_ID, _step.amount);
                    return _step.amount;
                }
                return 0;
            }
        }
        return 0;
    }

    function _moveItems(RecipeItem storage _item, address _from, address _to) private {
        if(_item.itemType == ItemType.ERC20) {
            if(_from == address(this)) {
                IERC20Upgradeable(_item.itemAddress).safeTransfer(_to, _item.amount);
            } else {
                IERC20Upgradeable(_item.itemAddress).safeTransferFrom(_from, _to, _item.amount);
            }
        } else { // 1155
            if(_item.itemAddress == address(consumable)) {
                consumable.adminSafeTransferFrom(_from, _to, _item.itemId, _item.amount);
            } else if(_item.itemAddress == address(balancerCrystal)) {
                balancerCrystal.adminSafeTransferFrom(_from, _to, _item.itemId, _item.amount);
            } else {
                IERC1155Upgradeable(_item.itemAddress).safeTransferFrom(_from, _to, _item.itemId, _item.amount, "");
            }
        }
    }

    function _performItemEffect(RecipeItem storage _item, address _from) private {
        if(_item.itemEffect == ItemEffect.BURN) {
            if(_item.itemType == ItemType.ERC20) {
                _moveItems(_item, _from, DEAD_ADDRESS);
            } else { // 1155
                if(_item.itemAddress == address(consumable)) {
                    consumable.adminBurn(_from, _item.itemId, _item.amount);
                } else {
                    _moveItems(_item, _from, DEAD_ADDRESS);
                }
            }
        } else if(_item.itemEffect == ItemEffect.MOVE_TO_TREASURY) {
            _moveItems(_item, _from, treasuryAddress);
        } else {
            revert("Bad Item Effect");
        }
    }

    function recipeIdsForBuilding(address _buildingAddress) external view returns(uint256[] memory) {
        return buildingAddressToInfo[_buildingAddress].recipeIds.values();
    }
}

struct StartRemovingCorruptionParams {
    address buildingAddress;
    uint256 recipeId;
    bytes[] customData;
}
