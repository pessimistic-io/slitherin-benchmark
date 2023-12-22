// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import { Ownable } from "./Ownable.sol";
import { OTCSwapContract } from "./OTCSwapContract.sol";
import { ICounterPartyRegistry } from "./ICounterPartyRegistry.sol";
import { ISubAccount } from "./ISubAccount.sol";

/**
 * @title Swap Contract manager
 */
contract OTCSwapContractManager is Ownable {

    //constant used for division
    uint256 constant private BIPS_DIVISOR = uint256(10000);
    uint256 constant private DECIMAL_DIVISOR = uint256(1000000);

    //struct to hold data for swap contract.
    struct SwapContractData {
        uint8 direction;
        address swapAddress;
        address underlyingToken;
        address collateralToken;
        address receiverSubAccount;
        address payerSubAccount;
        uint256 initialUnderlyingPrice;
        uint256 swapContractUnits;
    }

    /**
     * @notice The total number of swap contracts deployed
     */
    uint256 public totalSwapContracts;

    //fee collector address
    address public feeCollector;

    //counter party registry
    address public counterPartyRegistry;

    /**
     * @notice The loans deployed, mapped by index
     */
    mapping (uint256 => SwapContractData) public swapContracts;

    /**
     * @notice The total number of swap contracts granted to a receiver
     */
    mapping (address => uint256) public totalByReceiver;

    /**
     * @notice The total number of swap contracts granted to a payer
     */
    mapping (address => uint256) public totalByPayer;

    /**
     * @notice Swap contracts per receiver.
     */
    mapping (address => mapping (uint256 => uint256)) public swapContractsByReceiver;

    /**
     * @notice Swap contracts per payer.
     */
    mapping (address => mapping (uint256 => uint256)) public swapContractsByPayer;

    /**
     * @notice This event is fired whenever a new swap contract is deployed
     * @param newSwapContract The address of the newly created swap contract
     */
    event OTCSwapContractDeployed (address newSwapContract);

    /**
     * @notice initialize contract.
     * @param _feeCollectorAddr Address of the fee collector.
     * @param _counterPartyRegistryAddr Address of the counter party registry.
     */
    constructor(
        address _feeCollectorAddr,
        address _counterPartyRegistryAddr
    ){
        require(_feeCollectorAddr != address(0), '0 address');
        require(_counterPartyRegistryAddr != address(0), '0 address');
        
        feeCollector = _feeCollectorAddr;
        counterPartyRegistry = _counterPartyRegistryAddr;
    }

    /**
     * @notice Only called by active swap contract
     */
    modifier onlySwapContract() {
        require(ICounterPartyRegistry(counterPartyRegistry).getSwapContract(msg.sender), 'Only Swap Contract');
        _;
    }


    /**
     * @notice Deploys a new otc swap contract.
     * @param direction The direction of the swap contract. 0 for short, 1 for long.
     * @param operator The address of the operator.
     * @param underlyingToken The address of the underlying token used for the swap contract.
     * @param collateralToken The collateral token used for the swap contract.
     * @param receiverSubAccount The receiver sub account address.
     * @param payerSubAccount The payer sub account address.
     * @param initialUnderlyingPrice The initial underlying price for the swap contract.
     * @param swapContractUnits The amount of units for the swap contract.
     * @param receiverVariationMarginBips The initial margin provided by the receiver.
     * @param payerVariationMarginBips The intitial margin provided by the payer.
     * @param receiverOriginationFeeBips The receiver origination fee.
     * @param payerOriginationFeeBips The payer origination fee.
     */

    function deployOTCSwapContract(
        uint8 direction,
        address operator,
        address underlyingToken,
        address collateralToken,
        address receiverSubAccount,
        address payerSubAccount,
        uint256 initialUnderlyingPrice,
        uint256 swapContractUnits,
        uint256 receiverVariationMarginBips,
        uint256 payerVariationMarginBips,
        uint256 receiverOriginationFeeBips,
        uint256 payerOriginationFeeBips
    ) external onlyOwner {
        // Deploy a new loan
        OTCSwapContract otcSwapContract = new OTCSwapContract(
            direction,
            operator,
            address(this),
            underlyingToken,
            collateralToken,
            receiverSubAccount,
            payerSubAccount,
            totalSwapContracts,
            initialUnderlyingPrice,
            swapContractUnits,
            receiverVariationMarginBips,
            payerVariationMarginBips
        );
        // Update the records
        swapContracts[totalSwapContracts] = SwapContractData(direction, address(otcSwapContract), underlyingToken, collateralToken, receiverSubAccount, payerSubAccount, initialUnderlyingPrice, swapContractUnits);
        //push into receiver and payer mapping arrays
        swapContractsByReceiver[receiverSubAccount][totalByReceiver[receiverSubAccount]] = totalSwapContracts;
        swapContractsByPayer[payerSubAccount][totalByPayer[payerSubAccount]] = totalSwapContracts;
        //update
        totalSwapContracts++;
        totalByReceiver[receiverSubAccount]++;
        totalByPayer[payerSubAccount]++;
        //emit
        emit OTCSwapContractDeployed(address(otcSwapContract));
        //add the swap contract to the registry contract
        ICounterPartyRegistry(counterPartyRegistry).addSwapContract(address(otcSwapContract));
        //notional value
        uint256 notionalValue = (initialUnderlyingPrice * swapContractUnits) / DECIMAL_DIVISOR;
        // origination fees
        uint256 receiverOriginationFee = (notionalValue * receiverOriginationFeeBips) / BIPS_DIVISOR;
        uint256 payerOriginationFee = (notionalValue * payerOriginationFeeBips) / BIPS_DIVISOR;
        //transfer origination fees
        if (receiverOriginationFee > 0) {
            ISubAccount(receiverSubAccount).transferOriginationFee(collateralToken, receiverOriginationFee);
        }
        if (payerOriginationFee > 0) {
            ISubAccount(payerSubAccount).transferOriginationFee(collateralToken, payerOriginationFee);
        }
    }

    /**
     * @notice Return the swapContractData struct.
     */
    function updateSwapContractNotionalValue(uint256 swapIndex, uint256 newInitialUnderlyingPrice, uint256 newSwapContractUnits) external onlySwapContract
    {
        //state changes to swap contract data struct 
        swapContracts[swapIndex].initialUnderlyingPrice = newInitialUnderlyingPrice;
        swapContracts[swapIndex].swapContractUnits = newSwapContractUnits;
    } 

    /**
     * @notice Return the swapContractData struct.
     */
    function getSwapContractData(uint256 swapIndex) external view returns (SwapContractData memory)
    {
        return swapContracts[swapIndex];
    } 
}
