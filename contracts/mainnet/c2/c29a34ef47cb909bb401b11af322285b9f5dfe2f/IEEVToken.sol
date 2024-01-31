// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.6.12;

interface IEEVToken {
    function mint(address to, uint256 amount) external;
    function setAllowAllRecipients(bool allowAll) external;
    function addRecipient(address allowedAddress) external;
    function removeRecipient(address allowedAddress) external;
}

