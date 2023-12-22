pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0


import "./BaseEscrowTemplate.sol";
import "./LockPaymentCondition.sol";
import "./TransferNFTCondition.sol";
import "./EscrowPaymentCondition.sol";
import "./DIDRegistry.sol";

/**
 * @title Agreement Template
 * @author Nevermined
 *
 * @dev Implementation of NFT Sales Template
 *
 *      The NFT Sales template supports an scenario where a NFT owner
 *      can sell that asset to a new Owner.
 *      Anyone (consumer/provider/publisher) can use this template in order
 *      to setup an agreement allowing a NFT owner to transfer the asset ownership
 *      after some payment. 
 *      The template is a composite of 3 basic conditions: 
 *      - Lock Payment Condition
 *      - Transfer NFT Condition
 *      - Escrow Reward Condition
 * 
 *      This scenario takes into account royalties for original creators in the secondary market.
 *      Once the agreement is created, the consumer after payment can request the transfer of the NFT
 *      from the current owner for a specific DID. 
 */
contract NFTSalesTemplate is BaseEscrowTemplate {

    DIDRegistry internal didRegistry;
    LockPaymentCondition internal lockPaymentCondition;
    ITransferNFT internal transferCondition;
    EscrowPaymentCondition internal rewardCondition;

    // Force to have different bytecode from other templates
    function id() public pure returns (uint) {
        return 1;
    }


   /**
    * @notice initialize init the 
    *       contract with the following parameters.
    * @dev this function is called only once during the contract
    *       initialization. It initializes the ownable feature, and 
    *       set push the required condition types including 
    *       access secret store, lock reward and escrow reward conditions.
    * @param _owner contract's owner account address
    * @param _agreementStoreManagerAddress agreement store manager contract address
    * @param _lockPaymentConditionAddress lock reward condition contract address
    * @param _transferConditionAddress transfer NFT condition contract address
    * @param _escrowPaymentAddress escrow reward condition contract address    
    */
    function initialize(
        address _owner,
        address _agreementStoreManagerAddress,
        address _lockPaymentConditionAddress,
        address _transferConditionAddress,
        address payable _escrowPaymentAddress
    )
        external
        initializer()
    {
        require(
            _owner != address(0) &&
            _agreementStoreManagerAddress != address(0) &&
            _lockPaymentConditionAddress != address(0) &&
            _transferConditionAddress != address(0) &&
            _escrowPaymentAddress != address(0),
            'Invalid address'
        );

        OwnableUpgradeable.__Ownable_init();
        transferOwnership(_owner);

        agreementStoreManager = AgreementStoreManager(
            _agreementStoreManagerAddress
        );

        didRegistry = DIDRegistry(
            agreementStoreManager.getDIDRegistryAddress()
        );

        lockPaymentCondition = LockPaymentCondition(
            _lockPaymentConditionAddress
        );
        
        transferCondition = TransferNFTCondition(
            _transferConditionAddress
        );

        rewardCondition = EscrowPaymentCondition(
            _escrowPaymentAddress
        );

        conditionTypes.push(address(lockPaymentCondition));
        conditionTypes.push(address(transferCondition));
        conditionTypes.push(address(rewardCondition));
    }

    // price for nft. First address is the seller, second is nft contract, third is token for setting the price
    mapping(address => mapping(address => mapping(address => mapping(bytes32 => uint256)))) public nftPrice;

    function nftSale(address nftAddress, bytes32 nftId, address token, uint256 amount) external {
        nftPrice[_msgSender()][nftAddress][token][nftId] = amount;
    }

    function checkParamsTransfer(bytes[] memory _params, bytes32 lockPaymentConditionId, bytes32 _did) internal view returns (address) {
        bytes32 _did0;
        address payable _rewardAddress;
        address _tokenAddress;
        uint256[] memory _amounts;
        address[] memory _receivers;
        (_did0, _rewardAddress, _tokenAddress, _amounts, _receivers) = abi.decode(_params[0], (bytes32, address, address, uint256[], address[]));
        bytes32 _did1;
        address _nftReceiver;
        uint256 _nftAmount;
        bytes32 _lockPaymentCondition;
        address _nftContractAddress;
        (_did1,, _nftReceiver, _nftAmount, _lockPaymentCondition, _nftContractAddress) = abi.decode(_params[1], (bytes32, address, address, uint256, bytes32, address));

        require(_did0 == _did1 && _did == _did0, 'did mismatch');
        require(_lockPaymentCondition == lockPaymentConditionId, 'lock id mismatch');
        require(_rewardAddress == conditionTypes[2], 'reward not escrow');

        // _receivers[0] should be the seller of NFT
        require(nftPrice[_receivers[0]][_nftContractAddress][_tokenAddress][_did] != 0, 'not on sale');
        require(nftPrice[_receivers[0]][_nftContractAddress][_tokenAddress][_did]*_nftAmount <= _amounts[0], 'too small price');
        return _receivers[0];
    }

    function checkParamsEscrow(bytes[] memory _params, bytes32 lockPaymentId, bytes32 transferId) internal pure {
        bytes32 _did0;
        address payable _rewardAddress;
        address _tokenAddress;
        uint256[] memory _amounts;
        address[] memory _receivers;
        (_did0, _rewardAddress, _tokenAddress, _amounts, _receivers) = abi.decode(_params[0], (bytes32, address, address, uint256[], address[]));

        bytes32 _did2;
        uint256[] memory _amounts2;
        address[] memory _receivers2;
        // address _returnAddress;
        address _lockPaymentAddress;
        address _tokenAddress2;
        bytes32 _lockCondition;
        bytes32[] memory _releaseConditions;
        (
            _did2,
            _amounts2,
            _receivers2,
            ,// _returnAddress,
            _lockPaymentAddress, 
            _tokenAddress2,
            _lockCondition,
            _releaseConditions
        ) = abi.decode(_params[2], (bytes32, uint256[], address[], address, address, address, bytes32, bytes32[]));

        require(_lockCondition == lockPaymentId, 'lock mismatch 2');
        require(_releaseConditions.length == 1, 'bad release condition');
        require(keccak256(abi.encode(_did0, _tokenAddress, _amounts, _receivers)) == keccak256(abi.encode(_did2, _tokenAddress2, _amounts2, _receivers2)), 'escrow mismatch');
        require(_releaseConditions[0] == transferId, 'tranfer mismatch');
    } 

    // Need to check that the agreement is valid
    function createAgreementFulfill(
        bytes32 _id,
        bytes32 _did,
        uint[] memory _timeLocks,
        uint[] memory _timeOuts,
        address _accessConsumer,
        bytes[] memory _params
    ) external payable {
        bytes32 agreementId = keccak256(abi.encode(_id, _msgSender()));
        bytes32[] memory conditionIds = new bytes32[](3);
        uint256[] memory indices = new uint256[](2);
        address[] memory accounts = new address[](2);
        bytes[] memory params = new bytes[](2);
        accounts[0] = _msgSender();
        // accounts[1] = getSeller(_params[1]);
        for (uint i = 0; i < 2; i++) {
            indices[i] = i;
            params[i] = _params[i];
        }
        for (uint i = 0; i < 3; i++) {
            conditionIds[i] = keccak256(_params[i]);
        }
        bytes32 lockConditionId = keccak256(abi.encode(agreementId, conditionTypes[0], conditionIds[0]));
        bytes32 transferConditionId = keccak256(abi.encode(agreementId, conditionTypes[1], conditionIds[1]));
        // decode all params
        accounts[1] = checkParamsTransfer(_params, lockConditionId, _did);
        checkParamsEscrow(_params, lockConditionId, transferConditionId);

        super.createAgreementAndFulfill(_id, _did, conditionIds, _timeLocks, _timeOuts, _accessConsumer, indices, accounts, params);
    }
}

