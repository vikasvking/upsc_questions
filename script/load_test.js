// Load test: N students writing one test at the same time through the app's API (k6, https://k6.io).
//
// 1. On a staging copy of the site:  bin/rails "load_test:setup[500,TEST_ID]"
// 2. Copy tmp/load_test_tokens.json next to this file.
// 3. Run from your Mac (brew install k6):
//      k6 run -e BASE_URL=https://staging.example.com -e STUDENTS=500 script/load_test.js
// 4. Watch the server while it runs: htop (CPU), free -m (memory), bin/kamal logs.
// 5. Afterwards: bin/rails load_test:cleanup
//
// Each virtual student: starts the test, sends a heartbeat every 15 s (strict mode), answers one question
// every ANSWER_EVERY seconds (random choices), then opens the result. The summary shows response times:
// aim for p(95) under 1-2 s. Everyone starts within RAMP seconds, like a class pressing Start together.

import http from "k6/http";
import { check, sleep } from "k6";

const BASE = (__ENV.BASE_URL || "http://localhost:3000") + "/api/v1";
const STUDENTS = parseInt(__ENV.STUDENTS || "500", 10);
const ANSWER_EVERY = parseInt(__ENV.ANSWER_EVERY || "45", 10); // seconds per question
const RAMP = parseInt(__ENV.RAMP || "60", 10);                  // seconds for everyone to press Start
const HEARTBEAT = 15;

const data = JSON.parse(open("./load_test_tokens.json"));

export const options = {
  scenarios: {
    exam: {
      executor: "per-vu-iterations",
      vus: Math.min(STUDENTS, data.tokens.length),
      iterations: 1,
      maxDuration: "3h",
    },
  },
  thresholds: {
    http_req_failed: ["rate<0.01"],        // under 1% errors
    http_req_duration: ["p(95)<2000"],     // 95% of requests under 2 s
  },
};

function headers(token) {
  return { headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json", Accept: "application/json" } };
}

export default function () {
  const token = data.tokens[__VU - 1];
  const h = headers(token);
  sleep(Math.random() * RAMP); // students press Start at slightly different moments

  const start = http.post(`${BASE}/tests/${data.test_id}/start`, "{}", h);
  check(start, { "test started": (r) => r.status === 200 || r.status === 201 });
  const attemptToken = start.json("attempt_token");
  if (!attemptToken) return;

  const paper = http.get(`${BASE}/attempts/${attemptToken}`, h);
  check(paper, { "questions loaded": (r) => r.status === 200 });
  const questions = paper.json("questions") || [];
  const strict = paper.json("attempt.strict") === true;

  let sinceHeartbeat = 0;
  for (const q of questions) {
    // think about the question, sending heartbeats meanwhile
    let left = ANSWER_EVERY * (0.5 + Math.random());
    while (left > 0) {
      const step = Math.min(left, HEARTBEAT - sinceHeartbeat);
      sleep(step);
      left -= step;
      sinceHeartbeat += step;
      if (strict && sinceHeartbeat >= HEARTBEAT) {
        http.post(`${BASE}/attempts/${attemptToken}/heartbeat`, "{}", h);
        sinceHeartbeat = 0;
      }
    }
    const choice = ["A", "B", "C", "D"][Math.floor(Math.random() * 4)];
    const ans = http.post(`${BASE}/attempts/${attemptToken}/answer`,
      JSON.stringify({ question_id: q.id, choice: choice, duration_seconds: ANSWER_EVERY }), h);
    check(ans, { "answer saved": (r) => r.status === 200 });
  }

  http.post(`${BASE}/attempts/${attemptToken}/finish`, "{}", h);
  const result = http.get(`${BASE}/attempts/${attemptToken}/result`, h);
  check(result, { "result opened": (r) => r.status === 200 });
}
