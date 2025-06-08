#!/usr/bin/env python
"""
Proxy-Lite-3B Example
=====================

This example demonstrates how to use the proxy-lite-3b model directly
for web automation without requiring a separate proxy service.
"""

import argparse
import asyncio
import base64
import io
import json
import os
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional, Any

# Import required proxy-lite modules
from proxy_lite import Runner, RunnerConfig
from proxy_lite.gif_maker import create_run_gif
from proxy_lite.logger import logger


async def run_web_automation(
    query: str,
    homepage: str = "https://www.google.com",
    headless: bool = False,
    api_base: Optional[str] = None,
    model_id: str = "convergence-ai/proxy-lite-3b",
    output_dir: Optional[str] = None,
    viewport_width: int = 1280,
    viewport_height: int = 960,
    max_steps: int = 20,
) -> Dict[str, Any]:
    """
    Run a web automation task using the proxy-lite-3b model.
    
    Args:
        query: The query or task to perform
        homepage: The starting URL
        headless: Whether to run in headless mode or show the browser
        api_base: The API base URL (if None, uses default)
        model_id: The model ID to use
        output_dir: Directory to save screenshots and GIFs
        viewport_width: Width of the browser viewport
        viewport_height: Height of the browser viewport
        max_steps: Maximum number of steps to take
        
    Returns:
        Dict containing results of the automation
    """
    # Configure the runner
    config = RunnerConfig.from_dict({
        "environment": {
            "name": "webbrowser",
            "headless": headless,
            "homepage": homepage,
            "annotate_image": True,
            "include_html": True,
            "viewport_width": viewport_width,
            "viewport_height": viewport_height,
            "screenshot_delay": 1.5,
        },
        "solver": {
            "name": "simple",
            "agent": {
                "name": "proxy_lite",
                "client": {
                    "name": "convergence",
                    "model_id": model_id,
                    # Use provided API base or fallback to default
                    "api_base": api_base or os.environ.get(
                        "PROXY_LITE_API_BASE", 
                        "https://convergence-ai-demo-api.hf.space/v1"
                    ),
                },
            },
        },
        "max_steps": max_steps,
        "action_timeout": 300,
        "environment_timeout": 120,
        "task_timeout": 600,  # 10 minutes
        "verbose": True,
    })
    
    # Create the runner
    logger.info(f"🤖 Running web automation for query: {query}")
    runner = Runner(config=config)
    
    try:
        # Run the automation
        result = await runner.run(query)
        
        # Handle output directory
        if output_dir:
            output_path = Path(output_dir)
        else:
            output_path = Path(__file__).parent / "outputs"
        
        output_path.mkdir(parents=True, exist_ok=True)
        
        # Save the final screenshot if available
        screenshot_path = None
        gif_path = None
        
        if hasattr(result, 'observations') and result.observations:
            # Try to get the final screenshot
            try:
                if hasattr(result.observations[-1], "info") and "original_image" in result.observations[-1].info:
                    final_screenshot = result.observations[-1].info["original_image"]
                    screenshot_path = output_path / f"{result.run_id}.png"
                    with open(screenshot_path, "wb") as f:
                        f.write(base64.b64decode(final_screenshot))
                    logger.info(f"🤖 Final screenshot saved to {screenshot_path}")
                    
                    # Create and save GIF
                    gif_path = output_path / f"{result.run_id}.gif"
                    create_run_gif(result, gif_path, duration=1500)
                    logger.info(f"🤖 GIF saved to {gif_path}")
            except (KeyError, IndexError, Exception) as e:
                logger.warning(f"⚠️ Couldn't save screenshot/GIF: {str(e)}")
        
        # Extract the steps and look for final answer
        steps = []
        final_answer = None
        
        if hasattr(result, 'actions') and result.actions:
            for i, action in enumerate(result.actions):
                # Create step dict for result
                step_dict = {
                    "action": action.text if hasattr(action, "text") else "Unknown action",
                    "tool_calls": []
                }
                
                # Extract tool calls if they exist
                if hasattr(action, "tool_calls") and action.tool_calls:
                    for tool_call in action.tool_calls:
                        if hasattr(tool_call, "function"):
                            step_dict["tool_calls"].append({
                                "name": tool_call.function.get("name", "unknown"),
                                "arguments": tool_call.function.get("arguments", {})
                            })
                
                # Add step to list
                steps.append(step_dict)
            
            # Check if the last action is the final answer
            # In proxy-lite, the last action is usually the answer when task is complete
            if hasattr(result.actions[-1], "text"):
                last_action_text = result.actions[-1].text
                if not last_action_text.startswith("<observation>"):
                    final_answer = last_action_text
        
        # Extract the answer/response
        answer = None
        
        # First try to use the final answer from the last action
        if final_answer:
            answer = final_answer
            # Clean up multi-line whitespace
            answer = re.sub(r'\s+', ' ', answer)
            logger.info(f"Using answer from final action: {answer}")
        # Otherwise check result object
        elif hasattr(result, 'answer') and result.answer:
            answer = result.answer
            logger.info(f"Using answer from result.answer: {answer}")
        elif hasattr(result, 'response') and result.response:
            answer = result.response
            logger.info(f"Using answer from result.response: {answer}")
        else:
            # Generate a generic response
            answer = f"The automation attempted to {query} but did not provide a final answer after {len(steps)} steps."
            
            # Check if we hit a CAPTCHA
            captcha_detected = False
            for step in steps:
                if "CAPTCHA" in step.get("action", "") or "robot" in step.get("action", "").lower():
                    captcha_detected = True
                    break
            
            if captcha_detected:
                answer += " A CAPTCHA challenge was encountered, which prevented completing the task."
        
        # Return the results
        return {
            "query": query,
            "success": answer is not None and not answer.startswith("The automation attempted to"),
            "steps": steps,
            "steps_taken": len(steps),
            "answer": answer,
            "screenshot_path": str(screenshot_path) if screenshot_path else None,
            "gif_path": str(gif_path) if gif_path else None,
        }
    except Exception as e:
        logger.error(f"❌ Error during web automation: {str(e)}")
        # Return a minimal result dictionary with error information
        return {
            "query": query,
            "success": False,
            "steps": [],
            "steps_taken": 0,
            "answer": f"Error: {str(e)}",
            "screenshot_path": None,
            "gif_path": None,
        }


def main():
    """Parse command line arguments and run the web automation."""
    parser = argparse.ArgumentParser(description="Proxy-Lite-3B Web Automation Example")
    parser.add_argument(
        "query",
        type=str,
        help="The query or task to perform",
    )
    parser.add_argument(
        "--homepage",
        type=str,
        default="https://www.google.com",
        help="The starting URL (default: https://www.google.com)",
    )
    parser.add_argument(
        "--headless",
        action="store_true",
        help="Run in headless mode (no browser UI)",
    )
    parser.add_argument(
        "--api-base",
        type=str,
        default=None,
        help="The API base URL (default: environment variable or demo endpoint)",
    )
    parser.add_argument(
        "--model-id",
        type=str,
        default="convergence-ai/proxy-lite-3b",
        help="The model ID to use (default: convergence-ai/proxy-lite-3b)",
    )
    parser.add_argument(
        "--output-dir",
        type=str,
        default=None,
        help="Directory to save screenshots and GIFs",
    )
    parser.add_argument(
        "--viewport-width",
        type=int,
        default=1280,
        help="Width of the browser viewport (default: 1280)",
    )
    parser.add_argument(
        "--viewport-height",
        type=int,
        default=960,
        help="Height of the browser viewport (default: 960)",
    )
    parser.add_argument(
        "--max-steps",
        type=int,
        default=20,
        help="Maximum number of steps to take (default: 20)",
    )
    
    args = parser.parse_args()
    
    # Run the web automation
    result = asyncio.run(run_web_automation(
        query=args.query,
        homepage=args.homepage,
        headless=args.headless,
        api_base=args.api_base,
        model_id=args.model_id,
        output_dir=args.output_dir,
        viewport_width=args.viewport_width,
        viewport_height=args.viewport_height,
        max_steps=args.max_steps,
    ))
    
    # Display the results
    logger.info(f"🤖 Automation completed with {result['steps_taken']} steps")
    if result.get('answer'):
        logger.info(f"🤖 Answer: {result['answer']}")
    if result.get('screenshot_path'):
        logger.info(f"🤖 See final screenshot at: {result['screenshot_path']}")
    if result.get('gif_path'):
        logger.info(f"🤖 See animation at: {result['gif_path']}")


if __name__ == "__main__":
    main() 