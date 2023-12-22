// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.0;

import "./Ownable.sol";

interface IInsuranceFund {
    function getAllAmms() external view returns (IAmm[] memory);
}

interface IAmm {
    function nextFundingTime() external view returns (uint256);
}

interface IClearingHouse {
    function payFunding(address _amm) external;
}

contract Funding is Ownable {
    IInsuranceFund insuranceFund;
    IClearingHouse clearingHouse;

    constructor(address _insuranceFund, address _clearingHouse) {
        insuranceFund = IInsuranceFund(_insuranceFund);
        clearingHouse = IClearingHouse(_clearingHouse);
    }

    function updateBaseContracts(address _insuranceFund, address _clearingHouse) external onlyOwner {
        insuranceFund = IInsuranceFund(_insuranceFund);
        clearingHouse = IClearingHouse(_clearingHouse);
    }

    function check() external view returns (bool) {
        IAmm[] memory amms = insuranceFund.getAllAmms();

        for (uint256 i; i < amms.length; i++) {
            uint256 nextFundingTime = amms[i].nextFundingTime();
            if (nextFundingTime <= block.timestamp)
                return true;
        }

        return false;
    }

    function action() external {
        IAmm[] memory amms = insuranceFund.getAllAmms();

        for (uint256 i; i < amms.length; i++) {
            uint256 nextFundingTime = amms[i].nextFundingTime();
            if (nextFundingTime <= block.timestamp)
                clearingHouse.payFunding(address(amms[i]));
        }
    }
}

