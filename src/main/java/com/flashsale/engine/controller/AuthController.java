package com.flashsale.engine.controller;

import com.flashsale.engine.model.AppUser;
import com.flashsale.engine.model.dto.AuthRequest;
import com.flashsale.engine.model.dto.AuthResponse;
import com.flashsale.engine.repository.UserRepository;
import com.flashsale.engine.security.JwtService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.bind.annotation.*;

/**
 * AuthController — handles user registration and login.
 * Returns JWT tokens for authenticated sessions.
 */
@RestController
@RequestMapping("/api/auth")
@RequiredArgsConstructor
@Slf4j
public class AuthController {

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;
    private final JwtService jwtService;

    /**
     * POST /api/auth/register
     * Register a new user. Default role: CUSTOMER.
     */
    @PostMapping("/register")
    public ResponseEntity<AuthResponse> register(@RequestBody AuthRequest request) {
        if (userRepository.existsByUsername(request.getUsername())) {
            return ResponseEntity.status(HttpStatus.CONFLICT)
                    .body(AuthResponse.builder()
                            .message("Username already exists")
                            .build());
        }

        AppUser user = AppUser.builder()
                .username(request.getUsername())
                .password(passwordEncoder.encode(request.getPassword()))
                .role(AppUser.Role.CUSTOMER)
                .build();
        userRepository.save(user);

        String token = jwtService.generateToken(user);
        log.info("User registered: {}", user.getUsername());

        return ResponseEntity.status(HttpStatus.CREATED)
                .body(AuthResponse.builder()
                        .token(token)
                        .username(user.getUsername())
                        .role(user.getRole().name())
                        .message("Registration successful")
                        .build());
    }

    /**
     * POST /api/auth/register/admin
     * Register an admin user. In production, this would be protected.
     */
    @PostMapping("/register/admin")
    public ResponseEntity<AuthResponse> registerAdmin(@RequestBody AuthRequest request) {
        if (userRepository.existsByUsername(request.getUsername())) {
            return ResponseEntity.status(HttpStatus.CONFLICT)
                    .body(AuthResponse.builder()
                            .message("Username already exists")
                            .build());
        }

        AppUser user = AppUser.builder()
                .username(request.getUsername())
                .password(passwordEncoder.encode(request.getPassword()))
                .role(AppUser.Role.ADMIN)
                .build();
        userRepository.save(user);

        String token = jwtService.generateToken(user);
        log.info("Admin registered: {}", user.getUsername());

        return ResponseEntity.status(HttpStatus.CREATED)
                .body(AuthResponse.builder()
                        .token(token)
                        .username(user.getUsername())
                        .role(user.getRole().name())
                        .message("Admin registration successful")
                        .build());
    }

    /**
     * POST /api/auth/login
     * Authenticate and receive a JWT token.
     */
    @PostMapping("/login")
    public ResponseEntity<AuthResponse> login(@RequestBody AuthRequest request) {
        AppUser user = userRepository.findByUsername(request.getUsername())
                .orElse(null);

        if (user == null || !passwordEncoder.matches(request.getPassword(), user.getPassword())) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                    .body(AuthResponse.builder()
                            .message("Invalid username or password")
                            .build());
        }

        String token = jwtService.generateToken(user);
        log.info("User logged in: {}", user.getUsername());

        return ResponseEntity.ok(AuthResponse.builder()
                .token(token)
                .username(user.getUsername())
                .role(user.getRole().name())
                .message("Login successful")
                .build());
    }
}
