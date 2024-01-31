// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

//  ==========  External imports    ==========
import "./IERC721.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./Multicall.sol";
import "./AccessControlEnumerableUpgradeable.sol";
import "./UUPSUpgradeable.sol";
//  ==========  Internal imports    ==========

import "./IAirdropERC721.sol";

//  ==========  Features    ==========
import "./Ownable.sol";
import "./INFTDrop.sol";
// import "../sample/extensions/interface/IDynamicCollection.sol";

contract AirdropERC721 is
    Initializable,
    Ownable,
    Multicall,
    ReentrancyGuardUpgradeable,
    AccessControlEnumerableUpgradeable,
    UUPSUpgradeable,
    IAirdropERC721
{
    /*///////////////////////////////////////////////////////////////
                            State variables
    //////////////////////////////////////////////////////////////*/

    address public nftAddress;
    AirdropBatch[] public airdropBatches;

    /*///////////////////////////////////////////////////////////////
                    Constructor + initializer logic
    //////////////////////////////////////////////////////////////*/

     constructor() {
        _disableInitializers();
    }

    /// @dev Initiliazes the contract, like a constructor.
    function initialize(address _defaultAdmin, address tokenAddress) external initializer {
        __ReentrancyGuard_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _setupOwner(_defaultAdmin);
        _setupRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        _setUpNftContractAddress(tokenAddress);
    }

    /*///////////////////////////////////////////////////////////////
                        Generic contract logic
    //////////////////////////////////////////////////////////////*/

    /// @dev Returns the type of the contract.
    function contractType() external pure returns (bytes32) {
        return bytes32("AirdropERC721");
    }

    /// @dev Returns the version of the contract.
    function contractVersion() external pure returns (uint8) {
        return uint8(1);
    }

     /** @dev Function that should revert when `msg.sender` is not authorized to upgrade the contract. Called by
     * {upgradeTo} and {upgradeToAndCall}.*/
    function _authorizeUpgrade(address newImplementation) internal override 
    {}
    
    /*///////////////////////////////////////////////////////////////
                            Airdrop logic
    //////////////////////////////////////////////////////////////*/

    function addAirdropBatch(AirdropBatch calldata _batch) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_batch.amount == _batch.airdropList.length, "!Invalid batch");
        airdropBatches.push(_batch);
        
        emit AirdropBatchAdded(_batch);
    }

    function removeAirdropBatch(uint256 batchIndex) public onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 len = airdropBatches.length;
        require(batchIndex < len, "Invalid batchIndex");
        airdropBatches[batchIndex] = airdropBatches[len - 1];
        airdropBatches.pop();
    }

    function updateAirdropBatch(AirdropBatch calldata _batch, uint256 batchIndex) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 len = airdropBatches.length;
        require(batchIndex < len, "Invalid batchIndex");
        require(_batch.amount == _batch.airdropList.length, "!Invalid batch");
        require(airdropBatches[batchIndex].processedAmount == 0, "Already processed");
        airdropBatches[batchIndex] = _batch;
        emit AirdropBatchUpdated(_batch, batchIndex);
    }

    function airdrop(uint256 batchIndex) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(batchIndex < airdropBatches.length, "Invalid batchIndex");
        require(airdropBatches[batchIndex].processedAmount == 0, "processed Batch");
        require(nftAddress != address(0), "Invalid NFT address");
        
        bytes32[] memory proofs;
        INFTDrop.SalesPhase memory salesPhase = INFTDrop(nftAddress).salesPhases(airdropBatches[batchIndex].salesPhaseId);
       
        for (uint256 i = 0; i < airdropBatches[batchIndex].amount; i ++) {
            address recipient = airdropBatches[batchIndex].airdropList[i].recipient;
            try INFTDrop(nftAddress).claim(recipient, 1, proofs , salesPhase.quantityLimitPerWallet, airdropBatches[batchIndex].salesPhaseId) {
                airdropBatches[batchIndex].processedAmount += 1;
                airdropBatches[batchIndex].airdropList[i].status = AirdropStatus.PROCESSED;
                emit AirdropProcessed(recipient, nftAddress, batchIndex);
            } catch {
                airdropBatches[batchIndex].failedAmount += 1;
                airdropBatches[batchIndex].airdropList[i].status = AirdropStatus.FAILED;
                emit AidropFailed(recipient, nftAddress, batchIndex);
            }
        }
    }
    
    /*///////////////////////////////////////////////////////////////
                        Read methods
    //////////////////////////////////////////////////////////////*/

    function getBatchCount() public view returns(uint256) {
        return airdropBatches.length;
    }

    function getAirdropBatch(uint256 batchIndex) public view returns (AirdropBatch memory) {
        require (batchIndex < airdropBatches.length, "Invalid batchIndex");
        return airdropBatches[batchIndex];
    }

    function getAirdropListByIndex(uint256 batchIndex) public view returns(AirdropContent[] memory) {
        require (batchIndex < airdropBatches.length, "Invalid batchIndex");
        return airdropBatches[batchIndex].airdropList;
    }
   
    /*///////////////////////////////////////////////////////////////
                        Miscellaneous
    //////////////////////////////////////////////////////////////*/

    /// @dev Returns whether owner can be set in the given execution context.
    function _canSetOwner() internal view virtual override returns (bool) {
        return msg.sender == owner();
    }

    function _setUpNftContractAddress (address _nftAddress) public {
        nftAddress = _nftAddress;
        emit NFTAddressAdded(nftAddress);
    }
    receive() external payable {}
}

