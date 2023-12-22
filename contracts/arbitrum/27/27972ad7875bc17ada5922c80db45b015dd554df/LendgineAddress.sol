// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.5.0;

/// @notice Library for determining addresses with pure functions
/// @author Kyle Scott (https://github.com/Numoen/core/blob/master/src/libraries/LendgineAddress.sol)
/// @author Modified from Uniswap
/// (https://github.com/Uniswap/v3-periphery/blob/main/contracts/libraries/PoolAddress.sol)
library LendgineAddress {
    uint256 internal constant LENDGINE_INIT_CODE_HASH =
        8054571572302922885618570384591191227505583773137294873307445126469413235681;
    uint256 internal constant PAIR_INIT_CODE_HASH =
        84289029583122013135104186400691857567042175749078857529413445749029061110543;

    /// @notice The identifying key of the pool
    struct LendgineKey {
        address base;
        address speculative;
        uint256 baseScaleFactor;
        uint256 speculativeScaleFactor;
        uint256 upperBound;
    }

    function getLendgineKey(
        address base,
        address speculative,
        uint256 baseScaleFactor,
        uint256 speculativeScaleFactor,
        uint256 upperBound
    ) internal pure returns (LendgineKey memory) {
        return
            LendgineKey({
                base: base,
                speculative: speculative,
                baseScaleFactor: baseScaleFactor,
                speculativeScaleFactor: speculativeScaleFactor,
                upperBound: upperBound
            });
    }

    function computeLendgineAddress(
        address factory,
        address base,
        address speculative,
        uint256 baseScaleFactor,
        uint256 speculativeScaleFactor,
        uint256 upperBound
    ) internal pure returns (address) {
        address out = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            factory,
                            keccak256(
                                abi.encode(base, speculative, baseScaleFactor, speculativeScaleFactor, upperBound)
                            ),
                            bytes32(LENDGINE_INIT_CODE_HASH)
                        )
                    )
                )
            )
        );
        return out;
    }

    function computePairAddress(
        address factory,
        address base,
        address speculative,
        uint256 baseScaleFactor,
        uint256 speculativeScaleFactor,
        uint256 upperBound
    ) internal pure returns (address) {
        address out = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            factory,
                            keccak256(
                                abi.encode(base, speculative, baseScaleFactor, speculativeScaleFactor, upperBound)
                            ),
                            bytes32(PAIR_INIT_CODE_HASH)
                        )
                    )
                )
            )
        );
        return out;
    }
}

