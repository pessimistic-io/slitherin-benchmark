// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

import "./CrucibleToken.sol";

abstract contract CrucibleTokenDeployer is ICrucibleTokenDeployer {
    struct Parameters {
        address factory;
        address baseToken;
        uint64 feeOnTransferX10000;
        uint64 feeOnWithdrawX10000;
        string name;
        string symbol;
    }

    Parameters public override parameters;

    /**
     @notice Deploys a crucible token
     @param factory The factory
     @param baseToken The base token
     @param feeOnTransferX10000 Fee on transfer rate per 10k
     @param feeOnWithdrawX10000 Fee on withdraw rate per 10k
     @param name The name
     @param symbol The symbol
     @return token The deployed token address
     */
    function deploy(
        address factory,
        address baseToken,
        uint64 feeOnTransferX10000,
        uint64 feeOnWithdrawX10000,
        string memory name,
        string memory symbol
    ) internal returns (address token) {
        parameters = Parameters({
            factory: factory,
            baseToken: baseToken,
            feeOnTransferX10000: feeOnTransferX10000,
            feeOnWithdrawX10000: feeOnWithdrawX10000,
            name: name,
            symbol: symbol
        });

        token = address(
            new CrucibleToken{
                salt: keccak256(
                    abi.encode(
                        baseToken,
                        feeOnTransferX10000,
                        feeOnWithdrawX10000
                    )
                )
            }()
        );
        delete parameters;
    }
}

