//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;
import "./IERC20.sol";
import "./ISpecialPool.sol";
import "./SpecialPool.sol";
import "./SpecialValidatePoolLibrary.sol";

library SpecialDeployPoolLibrary {

    function deployPool() external returns (address poolAddress) {
        bytes memory bytecode = type(SpecialPool).creationCode;
        bytes32 salt = keccak256(
            abi.encodePacked(msg.sender, address(this), block.number)
        );
        assembly {
            poolAddress := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        return poolAddress;
    }

    function initPool(
        address poolAddress,
        address admin,
        ISpecialPool.PoolModel calldata poolInformation,
        uint256 poolTokenPercentFee,
        uint256 fundRaiseTokenDecimals
    ) external {
        IERC20 projectToken = IERC20(poolInformation.projectTokenAddress);
        uint256 totalTokenAmount = poolInformation
            .hardCap*poolInformation.specialSaleRate/(10**fundRaiseTokenDecimals);
        totalTokenAmount = totalTokenAmount+totalTokenAmount*poolTokenPercentFee/100;
        require(
            totalTokenAmount <= projectToken.balanceOf(msg.sender),
            "insufficient funds for transfer"
        );
        projectToken.transferFrom(msg.sender, poolAddress, totalTokenAmount);
        uint256 restToken = totalTokenAmount-(
            projectToken.balanceOf(poolAddress)
        );
        if (restToken > 0) {
            restToken = restToken*(totalTokenAmount)/(
                projectToken.balanceOf(poolAddress)
            );
            require(
                restToken <= projectToken.balanceOf(msg.sender),
                "insufficient funds for transfer"
            );
            projectToken.transferFrom(msg.sender, poolAddress, restToken);
        }
        if (msg.value > 0) {
            (bool sent, ) = payable(admin).call{value: msg.value}("");
            require(sent, "Failed to send Ether");
        }
    }

    function fillAdminPool(
        address poolAddress,
        ISpecialPool.PoolModel storage poolInformation,
        uint256 decimals,
        uint256 _weiRaised,
        uint256 fundRaiseTokenDecimals
    ) external {
        SpecialValidatePoolLibrary._poolIsFillable(poolInformation, _weiRaised);
        IERC20 projectToken = IERC20(poolInformation.projectTokenAddress);
        uint256 _balance = projectToken.balanceOf(poolAddress);
        poolInformation.specialSaleRate = poolInformation
            .specialSaleRate*(10**decimals)/(10**18);
        uint256 totalTokenAmount;
        if (
            poolInformation.status == ISpecialPool.PoolStatus.Collected ||
            (poolInformation.endDateTime <= block.timestamp &&
                poolInformation.status == ISpecialPool.PoolStatus.Inprogress &&
                poolInformation.softCap <= _weiRaised)
        ) {
            totalTokenAmount = _weiRaised*(poolInformation.specialSaleRate)/(10**fundRaiseTokenDecimals);
        } else {
            totalTokenAmount = poolInformation
                .hardCap*(poolInformation.specialSaleRate)/(10**fundRaiseTokenDecimals);
        }
        uint256 amountNeeded = totalTokenAmount-_balance;
        require(amountNeeded > 0, "already filled");
        require(
            amountNeeded <= projectToken.balanceOf(msg.sender),
            "insufficient funds for transfer"
        );
        projectToken.transferFrom(msg.sender, poolAddress, amountNeeded);
        uint256 restToken = totalTokenAmount-projectToken.balanceOf(poolAddress);
        if (restToken > 0) {
            restToken = restToken*(amountNeeded)/(
                projectToken.balanceOf(poolAddress)-(
                    totalTokenAmount-amountNeeded
                )
            );
            require(
                restToken <= projectToken.balanceOf(msg.sender),
                "insufficient funds for transfer"
            );
            projectToken.transferFrom(msg.sender, poolAddress, restToken);
        }
    }
}

