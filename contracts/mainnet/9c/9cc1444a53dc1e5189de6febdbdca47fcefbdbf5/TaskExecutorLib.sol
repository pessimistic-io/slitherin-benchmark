/*
 * This file is part of the Qomet Technologies contracts (https://github.com/qomet-tech/contracts).
 * Copyright (c) 2022 Qomet Technologies (https://qomet.tech)
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, version 3.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */
// SPDX-License-Identifier: GNU General Public License v3.0

pragma solidity 0.8.1;

import "./TaskExecutorInternal.sol";

library TaskExecutorLib {

    function _initialize(
        address newTaskManager
    ) internal {
        TaskExecutorInternal._initialize(newTaskManager);
    }

    function _getTaskManager(
        string memory taskManagerKey
    ) internal view returns (address) {
        return TaskExecutorInternal._getTaskManager(taskManagerKey);
    }

    function _executeTask(
        string memory key,
        uint256 taskId
    ) internal {
        TaskExecutorInternal._executeTask(key, taskId);
    }

    function _executeAdminTask(
        string memory key,
        uint256 adminTaskId
    ) internal {
        TaskExecutorInternal._executeAdminTask(key, adminTaskId);
    }
}

