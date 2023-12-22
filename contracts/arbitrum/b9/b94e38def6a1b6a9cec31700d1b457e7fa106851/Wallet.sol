// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.21;

import "./IERC20.sol";
import "./BaseWallet.sol";

contract Wallet is BaseWallet {
    IERC20 immutable JGLP;
    IERC20 immutable USDC_E;

    modifier walletAction() override {
        if (msg.sender == address(ENTRY_POINT)) {
            uint256 balance1 = JGLP.balanceOf(address(this));
            uint256 balance2 = USDC_E.balanceOf(address(this));
            _;
            require(JGLP.balanceOf(address(this)) >= balance1 || _userOpHashChallenge(keccak256("jGLP")), "No steal my monies!");
            require(USDC_E.balanceOf(address(this)) >= balance2 || _userOpHashChallenge(keccak256("USDC.e")), "No steal my monies!");
        } else if (msg.sender == WALLET) {
            _;
        } else {
            revert(ACCESS_DENIED);
        }
    }

    function _beforeMultiCall(Call[] calldata calls) internal view override {
        for (uint256 i = 0; i < calls.length; ++i) {
            require(calls[i].to != address(JGLP) || _userOpHashChallenge(keccak256("jGLP")), "No steal my monies!");
            require(calls[i].to != address(USDC_E) || _userOpHashChallenge(keccak256("USDC.e")), "No steal my monies!");
        }
    }

    constructor(
        IEntryPoint entryPoint,
        address signer,
        IERC20 jglp,
        IERC20 usdc_e,
        uint256 minGuardians,
        address guardian0,
        address guardian1,
        address guardian2,
        address guardian3
    )
        BaseWallet(
            entryPoint,
            signer,
            minGuardians,
            guardian0,
            guardian1,
            guardian2,
            guardian3
        )
    {
        JGLP = jglp;
        USDC_E = usdc_e;
    }
}

