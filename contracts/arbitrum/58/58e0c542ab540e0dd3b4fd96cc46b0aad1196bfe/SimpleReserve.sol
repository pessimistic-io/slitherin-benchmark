// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.17;

import { DSU as IDSU } from "./DSU.sol";
import "./Token18.sol";
import "./Token6.sol";
import "./UInitializable.sol";
import "./IReserve.sol";

contract SimpleReserve is IReserve, UInitializable {
    Token18 public immutable DSU; // solhint-disable-line var-name-mixedcase
    Token6 public immutable USDC; // solhint-disable-line var-name-mixedcase

    constructor(Token18 dsu_, Token6 usdc_) {
        DSU = dsu_;
        USDC = usdc_;
    }

    function initialize() external initializer(1) {
        IDSU dsu_ = IDSU(Token18.unwrap(DSU));
        if (dsu_.owner() != address(this)) {
            dsu_.acceptOwnership();
        }
    }

    function redeemPrice() public pure returns (UFixed18) {
        return UFixed18Lib.ONE;
    }

    function mint(UFixed18 amount) external {
        USDC.pull(msg.sender, amount, true);
        IDSU(Token18.unwrap(DSU)).mint(UFixed18.unwrap(amount));
        DSU.push(msg.sender, amount);

        emit Mint(msg.sender, amount, amount);
    }

    function redeem(UFixed18 amount) external {
        DSU.pull(msg.sender, amount);
        IDSU(Token18.unwrap(DSU)).burn(UFixed18.unwrap(amount));
        USDC.push(msg.sender, amount);

        emit Redeem(msg.sender, amount, amount);
    }

    function debt(address) external pure returns (UFixed18) {
        return UFixed18Lib.ZERO;
    }

    function repay(address, UFixed18) external pure {
        return;
    }
}

