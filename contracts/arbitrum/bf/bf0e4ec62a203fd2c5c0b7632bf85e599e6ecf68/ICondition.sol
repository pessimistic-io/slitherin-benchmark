pragma solidity ^0.8.0;
// Copyright 2022 Nevermined AG.
// SPDX-License-Identifier: (Apache-2.0 AND CC-BY-4.0)
// Code is Apache-2.0 and docs are CC-BY-4.0

interface ICondition {
    function fulfillProxy(
        address _account,
        bytes32 _agreementId,
        bytes memory params
    ) external payable;
}

