#!/bin/bash
# Runs the test suite without the model-backed LLM suites.
#
# `-skip-testing:` takes a class name, never a directory: `-skip-testing:LogueTests/LLMIntegration`
# is silently ignored, and those 16 suites run anyway — costing ~25 minutes and failing
# non-deterministically because they drive a real on-device model.
#
# Do not pipe this through `tail`/`head` when you care about the result: a pipeline's exit
# status is the last command's, so a failed run reports success.
set -uo pipefail

# Suite *type* names only. `-skip-testing:` takes a class name, never a filename and never a
# directory — an entry naming `DocumentLLMTests.swift` skips nothing while making the list look
# complete, so a suite added to that file would quietly run the model in the fast pass.
SKIP=""
for suite in \
  ClarityAnalysisLLMTests DailyDigestLLMTests DocumentChatLLMTests DocumentTitleLLMTests \
  FactCheckLLMTests GrammarAnalysisLLMTests MeetingChatLLMTests MeetingTitleLLMTests \
  PIIScanLLMTests RephraseLLMTests ReviewReactionsLLMTests ReviewScoreLLMTests \
  RewriteStyleLLMTests SmartMinutesLLMTests ToneDetectionLLMTests VocabularyEnhancementLLMTests; do
  SKIP="$SKIP -skip-testing:LogueTests/$suite"
done

# shellcheck disable=SC2086
xcodebuild test \
  -project Logue.xcodeproj \
  -scheme Logue \
  -destination 'platform=macOS' \
  $SKIP \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
