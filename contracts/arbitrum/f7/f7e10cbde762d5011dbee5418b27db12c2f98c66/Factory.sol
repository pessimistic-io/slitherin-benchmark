// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import { Lendgine } from "./Lendgine.sol";
import { Pair } from "./Pair.sol";

import { IFactory } from "./IFactory.sol";

contract Factory is IFactory {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event LendgineCreated(
        address indexed base,
        address indexed speculative,
        uint256 baseScaleFactor,
        uint256 speculativeScaleFactor,
        uint256 indexed upperBound,
        address lendgine,
        address pair
    );

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error SameTokenError();

    error ZeroAddressError();

    error DeployedError();

    error AddressError();

    /*//////////////////////////////////////////////////////////////
                            FACTORY STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IFactory
    mapping(address => mapping(address => mapping(uint256 => mapping(uint256 => mapping(uint256 => address)))))
        public
        override getLendgine;

    /*//////////////////////////////////////////////////////////////
                        TEMPORARY DEPLOY STORAGE
    //////////////////////////////////////////////////////////////*/

    struct Parameters {
        address lendgine;
        address base;
        address speculative;
        uint256 baseScaleFactor;
        uint256 speculativeScaleFactor;
        uint256 upperBound;
    }

    /// @inheritdoc IFactory
    Parameters public override pairParameters;

    /// @inheritdoc IFactory
    address public override pair;

    /*//////////////////////////////////////////////////////////////
                              FACTORY LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IFactory
    function createLendgine(
        address base,
        address speculative,
        uint256 baseScaleFactor,
        uint256 speculativeScaleFactor,
        uint256 upperBound
    ) external override returns (address, address) {
        if (speculative == base) revert SameTokenError();
        if (speculative == address(0) || base == address(0)) revert ZeroAddressError();
        if (getLendgine[base][speculative][baseScaleFactor][speculativeScaleFactor][upperBound] != address(0))
            revert DeployedError();

        address lendgineEstimate = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            address(this),
                            keccak256(
                                abi.encode(base, speculative, baseScaleFactor, speculativeScaleFactor, upperBound)
                            ),
                            keccak256(type(Lendgine).creationCode)
                        )
                    )
                )
            )
        );

        pairParameters = Parameters({
            lendgine: lendgineEstimate,
            base: base,
            speculative: speculative,
            baseScaleFactor: baseScaleFactor,
            speculativeScaleFactor: speculativeScaleFactor,
            upperBound: upperBound
        });

        address _pair = address(
            new Pair{
                salt: keccak256(abi.encode(base, speculative, baseScaleFactor, speculativeScaleFactor, upperBound))
            }()
        );
        pair = _pair;

        address _lendgine = address(
            new Lendgine{
                salt: keccak256(abi.encode(base, speculative, baseScaleFactor, speculativeScaleFactor, upperBound))
            }()
        );

        delete pair;
        delete pairParameters;

        if (lendgineEstimate != _lendgine) revert AddressError();
        getLendgine[base][speculative][baseScaleFactor][speculativeScaleFactor][upperBound] = _lendgine;
        emit LendgineCreated(base, speculative, baseScaleFactor, speculativeScaleFactor, upperBound, _lendgine, _pair);
        return (_lendgine, _pair);
    }
}

