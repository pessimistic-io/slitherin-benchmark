// SPDX-License-Identifier: UNLICENSED

/* *
 * Copyright (c) 2021-2023 LI LI @ JINGTIAN & GONGCHENG.
 *
 * This WORK is licensed under ComBoox SoftWare License 1.0, a copy of which 
 * can be obtained at:
 *         [https://github.com/paul-lee-attorney/comboox]
 *
 * THIS WORK IS PROVIDED ON AN "AS IS" BASIS, WITHOUT 
 * WARRANTIES OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED 
 * TO NON-INFRINGEMENT, MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE. IN NO 
 * EVENT SHALL ANY CONTRIBUTOR BE LIABLE TO YOU FOR ANY DAMAGES.
 *
 * YOU ARE PROHIBITED FROM DEPLOYING THE SMART CONTRACTS OF THIS WORK, IN WHOLE 
 * OR IN PART, FOR WHATEVER PURPOSE, ON ANY BLOCKCHAIN NETWORK THAT HAS ONE OR 
 * MORE NODES THAT ARE OUT OF YOUR CONTROL.
 * */

pragma solidity ^0.8.8;

import "./IFilesFolder.sol";

import "./AccessControl.sol";

contract FilesFolder is IFilesFolder, AccessControl {
    using FilesRepo for FilesRepo.Repo;

    FilesRepo.Repo internal _repo;

    //##################
    //##  Write I/O   ##
    //##################

    function regFile(bytes32 snOfDoc, address body)
        external onlyDK
    {
        if (_repo.regFile(snOfDoc, body)) 
            emit UpdateStateOfFile(body, uint8(FilesRepo.StateOfFile.Created));
    }

    function circulateFile(
        address body,
        uint16 signingDays,
        uint16 closingDays,
        RulesParser.VotingRule memory vr,
        bytes32 docUrl,
        bytes32 docHash
    ) external onlyKeeper {
        _repo.circulateFile(body, signingDays, closingDays, vr, docUrl, docHash);
        emit UpdateStateOfFile(body, uint8(FilesRepo.StateOfFile.Circulated));
    }

    function proposeFile(
        address body,
        uint64 seqOfMotion
    ) external onlyKeeper {
        _repo.proposeFile(body, seqOfMotion);
        emit UpdateStateOfFile(body, uint8(FilesRepo.StateOfFile.Proposed));
    }

    function voteCountingForFile(
        address body,
        bool approved
    ) external onlyKeeper {
        _repo.voteCountingForFile(body, approved);
        emit UpdateStateOfFile(body, approved ? 
                uint8(FilesRepo.StateOfFile.Approved) : 
                uint8(FilesRepo.StateOfFile.Rejected));
    }

    function execFile(
        address body
    ) public onlyDK {
        _repo.execFile(body);
        emit UpdateStateOfFile(body, uint8(FilesRepo.StateOfFile.Closed));
    }

    function terminateFile(
        address body
    ) public onlyDK {
        _repo.terminateFile(body);
        emit UpdateStateOfFile(body, uint8(FilesRepo.StateOfFile.Revoked));
    }

    function setStateOfFile(address body, uint state) public onlyKeeper {
        _repo.setStateOfFile(body, state);
        emit UpdateStateOfFile(body, state);
    }

    //##################
    //##   read I/O   ##
    //##################

    function signingDeadline(address body) external view returns (uint48) {
        return _repo.signingDeadline(body);
    }

    function closingDeadline(address body) external view returns (uint48) {                
        return _repo.closingDeadline(body);
    }

    function frExecDeadline(address body) external view returns (uint48) {
        return _repo.frExecDeadline(body);
    }

    function dtExecDeadline(address body) external view returns (uint48) {
        return _repo.dtExecDeadline(body);
    }

    function terminateStartpoint(address body) external view returns (uint48) {
        return _repo.terminateStartpoint(body);
    }

    function votingDeadline(address body) external view returns (uint48) {
        return _repo.votingDeadline(body);
    }    

    function isRegistered(address body) external view returns (bool) {
        return _repo.isRegistered(body);
    }

    function qtyOfFiles() external view returns (uint256) {
        return _repo.qtyOfFiles();
    }

    function getFilesList() external view returns (address[] memory) {
        return _repo.getFilesList();
    }

    function getFile(address body) external view returns (FilesRepo.File memory) {
        return _repo.getFile(body);
    } 

    function getHeadOfFile(address body)
        public view returns (FilesRepo.Head memory head)
    {
        head = _repo.getHeadOfFile(body);
    }

}

