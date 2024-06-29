//SPDX-Lincense-Identifier: MIT

pragma solidity ^0.8.20;

import { Test, console } from 'forge-std/Test.sol';
import { MyGovernor } from "../src/MyGovernor.sol";
import { Box } from "../src/Box.sol";
import { TimeLock } from "../src/TimeLock.sol";
import { GovToken } from "../src/GovToken.sol";

contract MyGovernorTest is Test {

    MyGovernor governor;
    Box box;
    TimeLock timelock;
    GovToken govToken;

    address public USER = makeAddr('user'); 
    uint256 public constant INITIAL_SUPPLY = 100 ether;
    uint256 public constant MIN_DELAY = 3600; // 1 hr after a vote passes
    uint256 public constant VOTING_DELAY = 1; // how many blocks till a vote is active
    uint256 public constant VOTING_PERIOD = 50400;

    address[] proposers;
    address[] executors;
    uint256[] values;
    bytes[] calldatas;
    address[] targets;
    
    function setUp() public {
         govToken = new GovToken();
         govToken.mint(USER, INITIAL_SUPPLY);       

         vm.startPrank(USER);
         govToken.delegate(USER); //user delegates token to themselves
         timelock = new TimeLock(MIN_DELAY, proposers, executors);
         governor = new MyGovernor(govToken, timelock);

         bytes32 proposerRole = timelock.PROPOSER_ROLE();
         bytes32 executorRole = timelock.EXECUTOR_ROLE();
         bytes32 adminRole = timelock.TIMELOCK_ADMIN_ROLE();

         timelock.grantRole(proposerRole, address(governor)); // only the governor can propose to the timelock
         timelock.grantRole(executorRole, address(0)); // anybody can execute a pass proposal
         timelock.revokeRole(adminRole, USER); // the USER should no longer be the admin
         vm.stopPrank();

         box = new Box();
         box.transferOwnership(address(timelock));
    }

    function testCantUpdateBoxWithoutGovernance() public {
        vm.expectRevert();
        box.store(1);
    }

    function testGovernanceUpdateBox() public {
        uint256 valueToStore = 888;
        string memory description = "store 1 in Box";
        calldatas.push(abi.encodeWithSignature("store(uint256)", valueToStore));
        values.push(0);
        targets.push(address(box));

        // 1. Propose to the DAO
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // view the state
        console.log("Proposal State: ", uint256(governor.state(proposalId)));
        
        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.roll(block.number + VOTING_DELAY + 1);

        console.log("Proposal State: ", uint256(governor.state(proposalId)));
        
        // 2. Now, we vote
        string memory reason = "cuz blue frog is cool";
        uint8 voteWay = 1; // this means we're voting for
        vm.prank(USER);
        governor.castVoteWithReason(proposalId, voteWay, reason);
    
        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);

        // 3. Queue the TX (same params as the proposalId, just that we have to queue it first)
        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        governor.queue(targets, values, calldatas, descriptionHash);

        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.warp(block.number + MIN_DELAY + 1);

        // 4. execute
        governor.execute(targets, values, calldatas, descriptionHash);

        console.log("Box Value: ", box.getNumber());
        assert(box.getNumber() == valueToStore);
    }   
}