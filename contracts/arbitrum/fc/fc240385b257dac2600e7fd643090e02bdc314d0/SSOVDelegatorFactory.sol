// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

// Contracts
import {Ownable} from "./Ownable.sol";
import {SSOVDelegator} from "./SSOVDelegator.sol";

// Library
import {Clones} from "./Clones.sol";

contract SSOVDelegatorFactory is Ownable {
    /// @dev ssov token address => ssov delegator address
    mapping(address => address) public ssovDelegators;

    /// @dev implementation address of the ssov delegator
    address public immutable implementationAddress;

    event SSOVDelegatorCreated(
        address _ssov,
        address _ssovToken,
        uint256 _exerciseFee,
        uint256 _exerciseFeeCap
    );

    constructor() {
        implementationAddress = address(new SSOVDelegator());
    }

    /// @dev Creates the SSOV Delegator for an SSOV
    /// @param _ssov address of SSOV
    /// @param _ssovToken address of the token of the SSOV
    /// @param _exerciseFee exercise fee for the user calling exercise
    /// @param _exerciseFeeCap max fee the user calling exercise can receive
    function create(
        address _ssov,
        address _ssovToken,
        uint256 _exerciseFee,
        uint256 _exerciseFeeCap
    ) external onlyOwner returns (address) {
        SSOVDelegator ssovDelegator = SSOVDelegator(
            payable(Clones.clone((implementationAddress)))
        );

        ssovDelegator.initialize(
            _ssov,
            _ssovToken,
            _exerciseFee,
            _exerciseFeeCap
        );

        ssovDelegator.transferOwnership(msg.sender);

        address ssovDelegatorAddress = address(ssovDelegator);

        ssovDelegators[_ssovToken] = ssovDelegatorAddress;

        emit SSOVDelegatorCreated(
            _ssov,
            _ssovToken,
            _exerciseFee,
            _exerciseFeeCap
        );

        return ssovDelegatorAddress;
    }
}

