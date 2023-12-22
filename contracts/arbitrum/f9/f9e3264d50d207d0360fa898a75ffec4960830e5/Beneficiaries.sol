// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Limiter, LimiterLibrary, Transfer} from "./Limiter.sol";
import {LinkedList, LinkedListLibrary} from "./LinkedList.sol";

using LimiterLibrary for Limiter;
using LinkedListLibrary for LinkedList;

struct InternalBeneficiary {
    address account;
    Limiter limiter;
    uint enabledAt;
}

using InternalBeneficiaryLibrary for InternalBeneficiary;

library InternalBeneficiaryLibrary {
    function convert(InternalBeneficiary storage self) internal view returns (Beneficiary memory) {
        return
            Beneficiary({
                account: self.account,
                enabledAt: self.enabledAt,
                limit: self.limiter.limit,
                remainingLimit: self.limiter.remainingLimit(),
                transfers: self.limiter.transfers()
            });
    }
}

struct Beneficiary {
    address account;
    uint enabledAt;
    uint limit;
    int remainingLimit;
    Transfer[] transfers;
}

struct Beneficiaries {
    LinkedList _keys;
    mapping(uint128 => InternalBeneficiary) _beneficiaries;
    mapping(address => uint128) _addressKeys;
}

using BeneficiariesLibrary for Beneficiaries;

library BeneficiariesLibrary {
    error BeneficiaryAlreadyExists(address beneficiary);
    error BeneficiaryNotEnabled(address beneficiary);
    error BeneficiaryNotDefined(address beneficiary);
    error BeneficiaryLimitExceeded(address beneficiary);

    function addBeneficiary(
        Beneficiaries storage self,
        address _beneficiary,
        uint _interval,
        uint _limit,
        uint _cooldown
    ) internal {
        if (self._addressKeys[_beneficiary] != 0) {
            revert BeneficiaryAlreadyExists(_beneficiary);
        }
        uint128 key = self._keys.generate();
        self._beneficiaries[key].account = _beneficiary;
        self._beneficiaries[key].enabledAt = block.timestamp + _cooldown;
        self._beneficiaries[key].limiter.interval = _interval;
        self._beneficiaries[key].limiter.limit = _limit;
        self._addressKeys[_beneficiary] = key;
    }

    function setBeneficiaryLimit(Beneficiaries storage self, address _beneficiary, uint _limit) internal {
        InternalBeneficiary storage beneficiary = _getBeneficiary(self, _beneficiary);
        beneficiary.limiter.limit = _limit;
    }

    function temporarilyIncreaseBeneficiaryLimit(
        Beneficiaries storage self,
        address _beneficiary,
        uint _limitIncrease
    ) internal {
        InternalBeneficiary storage beneficiary = _getBeneficiary(self, _beneficiary);
        beneficiary.limiter.temporarilyIncreaseLimit(_limitIncrease);
    }

    function temporarilyDecreaseBeneficiaryLimit(
        Beneficiaries storage self,
        address _beneficiary,
        uint _limitDecrease
    ) internal {
        InternalBeneficiary storage beneficiary = _getBeneficiary(self, _beneficiary);
        beneficiary.limiter.temporarilyDecreaseLimit(_limitDecrease);
    }

    function addBeneficiaryTransfer(Beneficiaries storage self, address _beneficiary, uint _amount) internal {
        InternalBeneficiary storage beneficiary = _getBeneficiary(self, _beneficiary);
        if (block.timestamp < beneficiary.enabledAt) {
            revert BeneficiaryNotEnabled(_beneficiary);
        }
        if (!beneficiary.limiter.addTransfer(_amount)) {
            revert BeneficiaryLimitExceeded(_beneficiary);
        }
    }

    function _getBeneficiaryKey(Beneficiaries storage self, address _beneficiary) private view returns (uint128) {
        uint128 key = self._addressKeys[_beneficiary];
        if (key == 0) {
            revert BeneficiaryNotDefined(_beneficiary);
        }
        return key;
    }

    function _getBeneficiary(
        Beneficiaries storage self,
        address _beneficiary
    ) private view returns (InternalBeneficiary storage) {
        return self._beneficiaries[_getBeneficiaryKey(self, _beneficiary)];
    }

    function getBeneficiary(
        Beneficiaries storage self,
        address _beneficiary
    ) internal view returns (Beneficiary memory) {
        return _getBeneficiary(self, _beneficiary).convert();
    }

    function removeBeneficiary(Beneficiaries storage self, address _beneficiary) internal {
        uint128 key = _getBeneficiaryKey(self, _beneficiary);
        delete self._beneficiaries[key];
        self._keys.remove(key);
    }

    function getBeneficiaries(Beneficiaries storage self) internal view returns (Beneficiary[] memory) {
        Beneficiary[] memory beneficiaries = new Beneficiary[](self._keys.length());
        uint index = 0;
        uint128 key = self._keys.first();
        while (key != 0) {
            beneficiaries[index] = self._beneficiaries[key].convert();
            key = self._keys.next(key);
            index++;
        }
        return beneficiaries;
    }
}

