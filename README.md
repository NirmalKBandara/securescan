# SecureScan

SecureScan is a secure API-managed network scanning platform built as a personal project to demonstrate modern API management, identity, integration, networking, and deployment practices.

## Project Overview

SecureScan allows authenticated users to submit authorized network scan requests and view their scan results through a web interface.

## Problem Statement

Network scanning tools can be difficult to manage securely. SecureScan aims to provide a controlled system with authentication, authorization, rate limiting, target validation, audit logging, and scan history.

## Main Features

- Secure user authentication
- Role-based access control
- Authorized target scanning
- API throttling
- Scan history
- Administrator dashboard
- Audit logging
- Docker-based local deployment

## Technology Stack

- Next.js
- TypeScript
- WSO2 Identity Server
- WSO2 API Manager
- Ballerina
- Go
- PostgreSQL
- Docker Compose

## Architecture

```text
User
  ↓
Next.js Frontend
  ↓
WSO2 Identity Server
  ↓
WSO2 API Manager
  ↓
Ballerina Integration API
  ↓
Go Scanner Engine
  ↓
PostgreSQL
```

## Current Status

The project is currently in the initial planning and setup stage.

## Security Notice

SecureScan is intended only for systems that the user owns or has explicit permission to test. Unauthorized scanning is prohibited.

## Roadmap

* [x] Initialize repository
* [x] Create project structure
* [ ] Refactor Go scanner engine
* [ ] Build Ballerina API
* [ ] Add PostgreSQL storage
* [ ] Build Next.js frontend
* [ ] Integrate WSO2 Identity Server
* [ ] Integrate WSO2 API Manager
* [ ] Add Docker Compose
* [ ] Add automated tests
* [ ] Complete documentation

