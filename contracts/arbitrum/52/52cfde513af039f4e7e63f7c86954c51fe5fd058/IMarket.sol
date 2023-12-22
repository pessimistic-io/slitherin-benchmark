// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

interface IMarket {
    struct Props {
        address marketToken;
        address indexToken;
        address longToken;
        address shortToken;
    }
}
