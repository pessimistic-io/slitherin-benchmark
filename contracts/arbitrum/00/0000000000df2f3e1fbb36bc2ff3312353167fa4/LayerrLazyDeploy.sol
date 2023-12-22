//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {ILayerrLazyDeploy} from "./ILayerrLazyDeploy.sol";
import {LayerrProxy} from "./LayerrProxy.sol";
import {ILayerrMinter} from "./ILayerrMinter.sol";
import {MintOrder} from "./MinterStructs.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {IERC20} from "./IERC20.sol";
import {IAdditionalRefundCalculator} from "./IAdditionalRefundCalculator.sol";


/**
 * @title LayerrLazyDeploy
 * @author 0xth0mas (Layerr)
 * @notice LayerrLazyDeploy allows for Layerr token contracts to be
 *         lazily deployed as late as in the same transaction that is 
 *         minting tokens on the contract.
 * 
 *         This allows for Layerr platform users to create collections
 *         and sign MintParameters without first deploying the token
 *         contract.
 *         
 *         Gas refunds for deployment and minting transactions are possible
 *         through gas sponsorships with a wide range of parameters for 
 *         controlling the refund amount and which transactions are eligible
 *         for a refund.
 * 
 *         Gas refund calculation logic is extensible with contracts that
 *         implement IAdditionalRefundCalculator to allow custom logic for
 *         refund amounts on L2s or for specific transactions.
 */
contract LayerrLazyDeploy is ILayerrLazyDeploy, ReentrancyGuard {

    /// @dev LayerrMinter interface
    ILayerrMinter public constant layerrMinter = ILayerrMinter(0x000000000000D58696577347F78259bD376F1BEC);

    /// @dev The next gas sponsorship ID that will be assigned when sponsorGas is called
    uint256 private nextGasSponsorshipId;
    /// @dev mapping of gas sponsorship IDs to the gas sponsorship data
    mapping(uint256 => GasSponsorship) public gasSponsorships;

    /**
     * @inheritdoc ILayerrLazyDeploy
     */
    function findDeploymentAddress(
        bytes32 salt,
        bytes calldata constructorArgs
    ) public view returns(address deploymentAddress) {
        bytes memory creationCode = _getCreationCode(constructorArgs);

        deploymentAddress = address(
            uint160(                    // downcast to match the address type.
                uint256(                  // convert to uint to truncate upper digits.
                    keccak256(              // compute the CREATE2 hash using 4 inputs.
                        abi.encodePacked(     // pack all inputs to the hash together.
                            hex"ff",            // start with 0xff to distinguish from RLP.
                            address(this),      // this contract will be the caller.
                            salt,               // pass in the supplied salt value.
                            keccak256(          // pass in the hash of initialization code.
                                abi.encodePacked(
                                creationCode
                                )
                            )
                        )
                    )
                )
            )
        );
    }

    /**
     * @inheritdoc ILayerrLazyDeploy
     */
    function deployContractAndMint(
        bytes32 salt,
        address expectedDeploymentAddress,
        bytes calldata constructorArgs,
        MintOrder[] calldata mintOrders,
        uint256 gasSponsorshipId
    ) external payable NonReentrant {
        uint256 startingBalance;
        if(gasSponsorshipId > 0) {
            startingBalance = _refundPrecheck(gasSponsorshipId);
        }
        uint256 gasUsedDeploy = _deployContract(salt, expectedDeploymentAddress, false, constructorArgs);
        uint256 gasUsedMint = _mint(mintOrders);
        if(gasSponsorshipId > 0) {
            _processGasRefund(gasSponsorshipId, startingBalance, gasUsedDeploy, gasUsedMint);
        }
    }

    /**
     * @inheritdoc ILayerrLazyDeploy
     */
    function deployContractAndMintWithERC20(
        bytes32 salt,
        address expectedDeploymentAddress,
        bytes calldata constructorArgs,
        MintOrder[] calldata mintOrders,
        LazyERC20Payment[] calldata erc20Payments,
        uint256 gasSponsorshipId
    ) external payable NonReentrant {
        uint256 startingBalance;
        if(gasSponsorshipId > 0) {
            startingBalance = _refundPrecheck(gasSponsorshipId);
        }
        _collectERC20ForMint(erc20Payments);
        uint256 gasUsedDeploy = _deployContract(salt, expectedDeploymentAddress, false, constructorArgs);
        uint256 gasUsedMint = _mint(mintOrders);
        _returnLeftoverERC20(erc20Payments);
        if(gasSponsorshipId > 0) {
            _processGasRefund(gasSponsorshipId, startingBalance, gasUsedDeploy, gasUsedMint);
        }
    }

    /**
     * @inheritdoc ILayerrLazyDeploy
     */
    function deployContract(
        bytes32 salt,
        address expectedDeploymentAddress,
        bool revertIfAlreadyDeployed,
        bytes calldata constructorArgs,
        uint256 gasSponsorshipId
    ) external NonReentrant {
        uint256 startingBalance;
        if(gasSponsorshipId > 0) {
            startingBalance = _refundPrecheck(gasSponsorshipId);
        }
        uint256 gasUsedDeploy = _deployContract(salt, expectedDeploymentAddress, revertIfAlreadyDeployed, constructorArgs);
        if(gasSponsorshipId > 0) {
            _processGasRefund(gasSponsorshipId, startingBalance, gasUsedDeploy, 0);
        }
    }

    /**
     * @inheritdoc ILayerrLazyDeploy
     */
    function mint(
        MintOrder[] calldata mintOrders,
        uint256 gasSponsorshipId
    ) external payable NonReentrant {
        uint256 startingBalance;
        if(gasSponsorshipId > 0) {
            startingBalance = _refundPrecheck(gasSponsorshipId);
        }
        uint256 gasUsedMint = _mint(mintOrders);
        if(gasSponsorshipId > 0) {
            _processGasRefund(gasSponsorshipId, startingBalance, 0, gasUsedMint);
        }
    }

    /**
     * @inheritdoc ILayerrLazyDeploy
     */
    function mintWithERC20(
        MintOrder[] calldata mintOrders,
        LazyERC20Payment[] calldata erc20Payments,
        uint256 gasSponsorshipId
    ) external payable NonReentrant {
        uint256 startingBalance;
        if(gasSponsorshipId > 0) {
            startingBalance = _refundPrecheck(gasSponsorshipId);
        }
        _collectERC20ForMint(erc20Payments);
        uint256 gasUsedMint = _mint(mintOrders);
        _returnLeftoverERC20(erc20Payments);
        if(gasSponsorshipId > 0) {
            _processGasRefund(gasSponsorshipId, startingBalance, 0, gasUsedMint);
        }
    }

    /**
     * @inheritdoc ILayerrLazyDeploy
     */
    function sponsorGas(
        uint24 baseRefundUnits,
        uint24 baseRefundUnitsDeploy,
        uint24 baseRefundUnitsMint,
        bool refundDeploy,
        bool refundMint,
        uint64 maxRefundUnitsDeploy,
        uint64 maxRefundUnitsMint,
        uint64 maxBaseFee,
        uint64 maxPriorityFee,
        address additionalRefundCalculator,
        address balanceCheckAddress,
        uint96 minimumBalanceIncrement
    ) external payable {
        GasSponsorship memory newSponsorship;
        newSponsorship.sponsor = msg.sender;
        newSponsorship.baseRefundUnits = baseRefundUnits;
        newSponsorship.baseRefundUnitsDeploy = baseRefundUnitsDeploy;
        newSponsorship.baseRefundUnitsMint = baseRefundUnitsMint;
        newSponsorship.refundDeploy = refundDeploy;
        newSponsorship.refundMint = refundMint;
        newSponsorship.maxRefundUnitsDeploy = maxRefundUnitsDeploy;
        newSponsorship.maxRefundUnitsMint = maxRefundUnitsMint;
        newSponsorship.maxBaseFee = maxBaseFee;
        newSponsorship.maxPriorityFee = maxPriorityFee;
        newSponsorship.donationAmount = uint96(msg.value);
        newSponsorship.additionalRefundCalculator = additionalRefundCalculator;
        newSponsorship.balanceCheckAddress = balanceCheckAddress;
        newSponsorship.minimumBalanceIncrement = minimumBalanceIncrement;

        unchecked {
            ++nextGasSponsorshipId;
        }
        gasSponsorships[nextGasSponsorshipId] = newSponsorship;
    }

    /**
     * @inheritdoc ILayerrLazyDeploy
     */
    function addToSponsorship(uint256 gasSponsorshipId) external payable {
        gasSponsorships[gasSponsorshipId].donationAmount += uint96(msg.value);
    }

    /**
     * @inheritdoc ILayerrLazyDeploy
     */
    function withdrawSponsorship(uint256 gasSponsorshipId) external {
        GasSponsorship storage gasSponsorship = gasSponsorships[gasSponsorshipId];

        if(msg.sender != gasSponsorship.sponsor) {
            revert CallerNotSponsor();
        }

        uint256 amountRemaining = gasSponsorship.donationAmount - gasSponsorship.amountUsed;
        gasSponsorship.donationAmount = gasSponsorship.amountUsed;

        (bool success, ) = payable(msg.sender).call{value: amountRemaining}("");
        if(!success) { revert SponsorshipWithdrawFailed(); }
    }

    /**
     * @dev Deploys a LayerrProxy contract with the provided `constructorArgs`
     */
    function _deployContract(
        bytes32 salt,
        address expectedDeploymentAddress,
        bool revertIfAlreadyDeployed,
        bytes calldata constructorArgs
    ) internal returns(uint256 gasUsed) {
        gasUsed = gasleft();

        uint256 existingCodeSize;
        /// @solidity memory-safe-assembly
        assembly {
            existingCodeSize := extcodesize(expectedDeploymentAddress)
        }
        if(existingCodeSize > 0) {
            if(revertIfAlreadyDeployed) {
                revert ContractAlreadyDeployed();
            } else {
                return 0;
            }
        }

        address deploymentAddress;
        bytes memory creationCode = _getCreationCode(constructorArgs);
        /// @solidity memory-safe-assembly
        assembly {
            deploymentAddress := create2(
                0,
                add(creationCode, 0x20),
                mload(creationCode),
                salt
            )
        }
        
        if(deploymentAddress != expectedDeploymentAddress) {
            revert DeploymentFailed();
        }
        unchecked {
            gasUsed -= gasleft();
        }
    }

    /**
     * @dev Gets the creation code for the LayerrProxy contract with `constructorArgs`
     */
    function _getCreationCode(bytes calldata constructorArgs) internal pure returns(bytes memory creationCode) {
        creationCode = type(LayerrProxy).creationCode;
        /// @solidity memory-safe-assembly
        assembly {
            calldatacopy(
                add(add(creationCode, 0x20), mload(creationCode)), 
                constructorArgs.offset, 
                constructorArgs.length
            )
            mstore(creationCode, add(mload(creationCode), constructorArgs.length))
            mstore(0x40, add(creationCode, mload(creationCode)))
        }
    }

    /**
     * @dev Calls LayerrMinter, calculates gas used and refunds overpayments
     */
    function _mint(
        MintOrder[] calldata mintOrders
    ) internal returns(uint256 gasUsed) {
        gasUsed = gasleft();
        uint256 balance = address(this).balance - msg.value;

        layerrMinter.mintBatchTo{value: msg.value}(msg.sender, mintOrders, 0);
        
        unchecked {
            balance -= address(this).balance;
        }
        if(balance > 0) {
            (bool success, ) = payable(msg.sender).call{value: balance}("");
            if(!success) revert RefundFailed();
        }
        unchecked {
            gasUsed -= gasleft();
        }
    }

    /**
     * @dev Collects ERC20 tokens from the caller, approves payment to LayerrMinter
     */
    function _collectERC20ForMint(LazyERC20Payment[] calldata erc20Payments) internal {
        for(uint256 paymentIndex;paymentIndex < erc20Payments.length;) {
            LazyERC20Payment calldata erc20Payment = erc20Payments[paymentIndex];
            address tokenAddress = erc20Payment.tokenAddress;
            uint256 totalSpend = erc20Payment.totalSpend;
            IERC20(tokenAddress).transferFrom(msg.sender, address(this), totalSpend);
            IERC20(tokenAddress).approve(address(layerrMinter), totalSpend);
            
            unchecked {
                ++paymentIndex;
            }
        }
    }

    /**
     * @dev Returns leftover ERC20 tokens to the caller, clears approvals
     */
    function _returnLeftoverERC20(LazyERC20Payment[] calldata erc20Payments) internal {
        for(uint256 paymentIndex;paymentIndex < erc20Payments.length;) {
            LazyERC20Payment calldata erc20Payment = erc20Payments[paymentIndex];
            address tokenAddress = erc20Payment.tokenAddress;
            uint256 remainingBalance = IERC20(tokenAddress).balanceOf(address(this));
            if(remainingBalance > 0) {
                IERC20(tokenAddress).transfer(msg.sender, remainingBalance);
                IERC20(tokenAddress).approve(address(layerrMinter), 0);
            }

            unchecked {
                ++paymentIndex;
            }
        }
    }

    /**
     * @dev Calculates and sends a gas refund to the caller
     */
    function _processGasRefund(uint256 gasSponsorshipId, uint256 startingBalance, uint256 gasUsedDeploy, uint256 gasUsedMint) internal {
        GasSponsorship memory gasSponsorship = gasSponsorships[gasSponsorshipId];

        if(gasSponsorship.balanceCheckAddress != address(0)) {
            if(gasSponsorship.balanceCheckAddress.balance < (startingBalance + gasSponsorship.minimumBalanceIncrement)) {
                return;
            }
        }

        uint256 refundUnits = gasSponsorship.baseRefundUnits;
        if(gasUsedDeploy > 0 && gasSponsorship.refundDeploy) {
            if(gasSponsorship.maxRefundUnitsDeploy < gasUsedDeploy) {
                gasUsedDeploy = gasSponsorship.maxRefundUnitsDeploy;
            }
            unchecked {
                refundUnits = (gasUsedDeploy + gasSponsorship.baseRefundUnitsDeploy);
            }
        }
        
        if(gasUsedMint > 0 && gasSponsorship.refundMint) {
            if(gasSponsorship.maxRefundUnitsMint < gasUsedMint) {
                gasUsedMint = gasSponsorship.maxRefundUnitsMint;
            }
            unchecked {
                refundUnits += (gasUsedMint + gasSponsorship.baseRefundUnitsMint);
            }
        }

        uint256 totalFee = block.basefee;
        if(totalFee > gasSponsorship.maxBaseFee) {
            totalFee = gasSponsorship.maxBaseFee;
        }
        uint256 priorityFee = tx.gasprice - block.basefee;
        if(priorityFee > gasSponsorship.maxPriorityFee) {
            priorityFee = gasSponsorship.maxPriorityFee;
        }
        unchecked {
            totalFee += priorityFee;
        }
        uint256 refundAmount = refundUnits * totalFee;

        if(gasSponsorship.additionalRefundCalculator != address(0)) {
            unchecked {
                uint256 calldataLength;
                /// @solidity memory-safe-assembly
                assembly {
                    calldataLength := calldatasize()
                }
                refundAmount += IAdditionalRefundCalculator(gasSponsorship.additionalRefundCalculator)
                    .calculateAdditionalRefundAmount(msg.sender, calldataLength, gasUsedDeploy, gasUsedMint);   
            }
        }

        uint256 donationRemaining;
        unchecked {
            donationRemaining = gasSponsorship.donationAmount - gasSponsorship.amountUsed;
        }
        if(refundAmount > donationRemaining) {
            refundAmount = donationRemaining;
        }

        gasSponsorships[gasSponsorshipId].amountUsed += uint96(refundAmount);
        (bool success, ) = payable(msg.sender).call{value: refundAmount}("");
        if(!success) revert RefundFailed();
    }

    /**
     * @dev Initiates pre-checks for gas refunds
     */
    function _refundPrecheck(uint256 gasSponsorshipId) internal returns (uint256 startingBalance) {
        address additionalRefundCalculator = gasSponsorships[gasSponsorshipId].additionalRefundCalculator;
        if(additionalRefundCalculator != address(0)) {
            IAdditionalRefundCalculator(additionalRefundCalculator).additionalRefundPrecheck();
        }
        address balanceCheckAddress = gasSponsorships[gasSponsorshipId].balanceCheckAddress;
        if(balanceCheckAddress != address(0)) {
            startingBalance = balanceCheckAddress.balance;
        }
    }
}
